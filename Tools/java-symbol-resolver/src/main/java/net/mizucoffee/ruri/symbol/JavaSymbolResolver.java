package net.mizucoffee.ruri.symbol;

import com.github.javaparser.JavaParser;
import com.github.javaparser.ParserConfiguration;
import com.github.javaparser.Position;
import com.github.javaparser.ast.CompilationUnit;
import com.github.javaparser.ast.ImportDeclaration;
import com.github.javaparser.ast.Node;
import com.github.javaparser.ast.body.*;
import com.github.javaparser.ast.expr.*;
import com.github.javaparser.ast.nodeTypes.NodeWithName;
import com.github.javaparser.ast.nodeTypes.NodeWithSimpleName;
import com.github.javaparser.ast.type.ClassOrInterfaceType;
import com.github.javaparser.resolution.UnsolvedSymbolException;
import com.github.javaparser.resolution.declarations.*;
import com.github.javaparser.resolution.types.ResolvedReferenceType;
import com.github.javaparser.resolution.types.ResolvedType;
import com.github.javaparser.symbolsolver.javaparsermodel.JavaParserFacade;
import com.github.javaparser.symbolsolver.JavaSymbolSolver;
import com.github.javaparser.symbolsolver.resolution.typesolvers.CombinedTypeSolver;
import com.github.javaparser.symbolsolver.resolution.typesolvers.JavaParserTypeSolver;
import com.github.javaparser.symbolsolver.resolution.typesolvers.JarTypeSolver;
import com.github.javaparser.symbolsolver.resolution.typesolvers.ReflectionTypeSolver;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;

final class JavaSymbolResolver {
    // 参照検索は1要求で多数のファイルをパースするため、TypeSolverのキャッシュを
    // 無制限にするとヒープを使い切る。1要求で解決に触れる型数より十分大きい値。
    private static final long TYPE_SOLVER_CACHE_LIMIT = 1_000;

    ResolverResponse resolve(ResolverRequest request) throws IOException {
        try {
            return doResolve(request);
        } finally {
            // JavaParserFacadeのstaticマップは値(facade)がキー(TypeSolver)を強参照する
            // ためWeakHashMapでも回収されず、要求ごとのTypeSolverとパース済みASTが
            // 蓄積してOutOfMemoryErrorに至る。要求単位で必ず破棄する。
            JavaParserFacade.clearInstances();
        }
    }

    private ResolverResponse doResolve(ResolverRequest request) throws IOException {
        if (request == null) {
            throw new IllegalArgumentException("Missing request payload.");
        }

        Path projectPath = Path.of(request.projectPath()).toAbsolutePath().normalize();
        Path filePath = Path.of(request.filePath()).toAbsolutePath().normalize();
        if (!filePath.toString().endsWith(".java")) {
            return emptyResponse();
        }

        Map<Path, String> overlays = overlayTexts(request);
        String sourceText = overlays.getOrDefault(filePath, request.text());
        Identifier identifier = Identifier.at(sourceText, request.utf16Offset());
        if (identifier == null || identifier.name().isEmpty()) {
            return emptyResponse();
        }

        List<Path> sourceRoots = sourceRoots(request, projectPath, filePath);
        ResolverRuntime runtime = runtime(projectPath, sourceRoots, request.classpath());
        Optional<CompilationUnit> selectedUnit = runtime.parser().parse(sourceText).getResult();
        if (selectedUnit.isEmpty()) {
            return emptyResponse();
        }

        selectedUnit.get().setStorage(filePath);
        Optional<SimpleName> selectedName = selectedName(selectedUnit.get(), sourceText, identifier.range());
        if (selectedName.isEmpty()) {
            Optional<SymbolTarget> importTarget = importTarget(
                selectedUnit.get(),
                sourceText,
                identifier.range(),
                runtime.typeSolver(),
                sourceRoots,
                filePath,
                overlays
            );
            if (importTarget.isPresent()) {
                if ("hover".equals(request.command())) {
                    return new ResolverResponse(null, null, List.of(), identifier.range(), false, List.of());
                }
                return new ResolverResponse("implementation", importTarget.get(), List.of(), null, false, List.of());
            }
            return emptyResponse();
        }
        if (isDeclarationName(selectedName.get())) {
            Optional<Node> declarationNode = declarationNode(selectedName.get());
            if (declarationNode.isEmpty()) {
                return emptyResponse();
            }
            Optional<SymbolTarget> definition = targetFor(declarationNode.get(), filePath, sourceText, overlays);
            if (definition.isEmpty()) {
                return emptyResponse();
            }
            if (!hasReferenceSearch(request)) {
                return new ResolverResponse(null, null, List.of(), null, true, List.of());
            }

            List<SymbolTarget> references = referencesFor(
                identifier,
                definition.get(),
                request,
                runtime,
                sourceRoots,
                filePath,
                sourceText,
                overlays
            );
            if ("hover".equals(request.command())) {
                TextRange hoverRange = references.isEmpty() ? null : identifier.range();
                return new ResolverResponse(null, null, List.of(), hoverRange, false, List.of());
            }
            return references.isEmpty()
                ? emptyResponse()
                : new ResolverResponse("references", null, references, null, false, List.of());
        }

        Optional<SymbolTarget> target = resolveTarget(selectedName.get(), runtime.typeSolver(), sourceRoots, filePath, sourceText, overlays);
        if (target.isEmpty()) {
            target = lexicalTarget(selectedUnit.get(), sourceText, identifier.range(), filePath, overlays);
        }
        if (target.isEmpty()) {
            return emptyResponse();
        }

        if ("hover".equals(request.command())) {
            return new ResolverResponse(null, null, List.of(), identifier.range(), false, List.of());
        }

        return new ResolverResponse("implementation", target.get(), List.of(), null, false, List.of());
    }

    private ResolverResponse emptyResponse() {
        return new ResolverResponse(null, null, List.of(), null, false, List.of());
    }

    private ResolverRuntime runtime(Path projectPath, List<Path> sourceRoots, List<String> classpath) {
        CombinedTypeSolver typeSolver = new CombinedTypeSolver(new ReflectionTypeSolver(false));
        // symbol resolverを設定しない素の構成にする(CombinedTypeSolver側の解決と
        // 再帰しないようにするため)。言語レベルはメインのパーサーと揃える。
        ParserConfiguration solverConfiguration = new ParserConfiguration()
            .setLanguageLevel(ParserConfiguration.LanguageLevel.JAVA_17);
        for (Path sourceRoot : sourceRoots) {
            if (!Files.isDirectory(sourceRoot)) {
                continue;
            }
            try {
                typeSolver.add(new JavaParserTypeSolver(sourceRoot, solverConfiguration, TYPE_SOLVER_CACHE_LIMIT));
            } catch (Exception ignored) {
            }
        }
        if (classpath != null) {
            for (String entry : classpath) {
                if (entry == null || entry.isBlank() || !entry.endsWith(".jar")) {
                    continue;
                }
                try {
                    typeSolver.add(new JarTypeSolver(entry));
                } catch (Exception ignored) {
                }
            }
        }

        ParserConfiguration configuration = new ParserConfiguration()
            .setLanguageLevel(ParserConfiguration.LanguageLevel.JAVA_17)
            .setSymbolResolver(new JavaSymbolSolver(typeSolver));
        return new ResolverRuntime(new JavaParser(configuration), typeSolver);
    }

    private List<Path> sourceRoots(ResolverRequest request, Path projectPath, Path filePath) {
        LinkedHashSet<Path> roots = new LinkedHashSet<>();
        roots.add(projectPath);
        if (request.sourceRoots() != null) {
            for (String sourceRoot : request.sourceRoots()) {
                if (sourceRoot == null || sourceRoot.isBlank()) {
                    continue;
                }
                roots.add(Path.of(sourceRoot).toAbsolutePath().normalize());
            }
        }
        Path parent = filePath.getParent();
        if (parent != null) {
            roots.add(parent.toAbsolutePath().normalize());
        }
        return List.copyOf(roots);
    }

    private Map<Path, String> overlayTexts(ResolverRequest request) {
        if (request.openDocuments() == null) {
            return Map.of();
        }

        Map<Path, String> overlays = new HashMap<>();
        for (OpenDocument document : request.openDocuments()) {
            if (document.path() == null || document.text() == null || !document.path().endsWith(".java")) {
                continue;
            }
            overlays.put(Path.of(document.path()).toAbsolutePath().normalize(), document.text());
        }
        return overlays;
    }

    private Optional<SimpleName> selectedName(CompilationUnit unit, String sourceText, TextRange range) {
        return unit.findAll(SimpleName.class).stream()
            .filter(name -> name.getRange()
                .map(nodeRange -> TextRanges.from(sourceText, nodeRange.begin, nodeRange.end))
                .map(nodeRange -> rangesTouch(nodeRange, range))
                .orElse(false))
            .min(Comparator.comparingInt(name -> name.getRange()
                .map(nodeRange -> TextRanges.from(sourceText, nodeRange.begin, nodeRange.end).length())
                .orElse(Integer.MAX_VALUE)));
    }

    private boolean isDeclarationName(SimpleName name) {
        return declarationNode(name).isPresent();
    }

    private Optional<Node> declarationNode(SimpleName name) {
        Optional<Node> parent = name.getParentNode();
        if (parent.isEmpty()) {
            return Optional.empty();
        }
        Node node = parent.get();
        return node instanceof TypeDeclaration<?>
            || node instanceof MethodDeclaration
            || node instanceof ConstructorDeclaration
            || node instanceof VariableDeclarator
            || node instanceof Parameter
            || node instanceof EnumConstantDeclaration
            || node instanceof AnnotationMemberDeclaration
            ? Optional.of(node)
            : Optional.empty();
    }

    private boolean hasReferenceSearch(ResolverRequest request) {
        return request.sourceFiles() != null && !request.sourceFiles().isEmpty();
    }

    private List<SymbolTarget> referencesFor(
        Identifier identifier,
        SymbolTarget definition,
        ResolverRequest request,
        ResolverRuntime runtime,
        List<Path> sourceRoots,
        Path selectedFilePath,
        String selectedText,
        Map<Path, String> overlays
    ) throws IOException {
        List<SymbolTarget> references = new ArrayList<>();
        Set<String> seen = new HashSet<>();
        int limit = request.referenceLimit() == null ? Integer.MAX_VALUE : Math.max(0, request.referenceLimit());
        if (limit == 0) {
            return List.of();
        }

        for (Path sourceFile : sourceFiles(request, selectedFilePath, overlays)) {
            String text;
            try {
                text = textFor(sourceFile, selectedFilePath, selectedText, overlays);
            } catch (IOException ignored) {
                continue;
            }
            if (!text.contains(identifier.name())) {
                continue;
            }

            Optional<CompilationUnit> unit = runtime.parser().parse(text).getResult();
            if (unit.isEmpty()) {
                continue;
            }
            unit.get().setStorage(sourceFile);

            references.addAll(importReferences(
                unit.get(),
                text,
                identifier,
                definition,
                runtime.typeSolver(),
                sourceRoots,
                sourceFile,
                selectedFilePath,
                selectedText,
                overlays,
                seen,
                limit - references.size()
            ));
            if (references.size() >= limit) {
                break;
            }

            for (SimpleName candidate : unit.get().findAll(SimpleName.class)) {
                if (!candidate.asString().equals(identifier.name()) || isDeclarationName(candidate)) {
                    continue;
                }
                Optional<TextRange> candidateRange = candidate.getRange()
                    .map(range -> TextRanges.from(text, range.begin, range.end));
                if (candidateRange.isEmpty()) {
                    continue;
                }

                Optional<SymbolTarget> resolved = referenceTarget(
                    candidate,
                    definition,
                    runtime.typeSolver(),
                    sourceRoots,
                    sourceFile,
                    text,
                    overlays
                );
                if (resolved.isEmpty() || !sameTarget(definition, resolved.get())) {
                    continue;
                }

                String key = sourceFile + ":" + candidateRange.get().location() + ":" + candidateRange.get().length();
                if (!seen.add(key)) {
                    continue;
                }
                references.add(new SymbolTarget(
                    sourceFile.toUri().toString(),
                    candidateRange.get(),
                    identifier.name(),
                    "usage"
                ));
                if (references.size() >= limit) {
                    break;
                }
            }
            if (references.size() >= limit) {
                break;
            }
        }

        return references;
    }

    private List<Path> sourceFiles(ResolverRequest request, Path selectedFilePath, Map<Path, String> overlays) {
        LinkedHashSet<Path> files = new LinkedHashSet<>();
        if (request.sourceFiles() != null) {
            for (String sourceFile : request.sourceFiles()) {
                if (sourceFile == null || sourceFile.isBlank() || !sourceFile.endsWith(".java")) {
                    continue;
                }
                files.add(Path.of(sourceFile).toAbsolutePath().normalize());
            }
        }
        files.add(selectedFilePath);
        files.addAll(overlays.keySet());
        return List.copyOf(files);
    }

    private List<SymbolTarget> importReferences(
        CompilationUnit unit,
        String text,
        Identifier identifier,
        SymbolTarget definition,
        CombinedTypeSolver typeSolver,
        List<Path> sourceRoots,
        Path sourceFile,
        Path selectedFilePath,
        String selectedText,
        Map<Path, String> overlays,
        Set<String> seen,
        int limit
    ) throws IOException {
        if (limit <= 0 || !"type".equals(definition.kind())) {
            return List.of();
        }

        List<SymbolTarget> references = new ArrayList<>();
        for (ImportDeclaration importDeclaration : unit.getImports()) {
            if (importDeclaration.isAsterisk()) {
                continue;
            }
            String qualifiedName = importDeclaration.getNameAsString();
            String simpleName = qualifiedName.substring(qualifiedName.lastIndexOf('.') + 1);
            if (!simpleName.equals(identifier.name())) {
                continue;
            }

            Optional<Node> resolved = resolveImport(importDeclaration, typeSolver, sourceRoots);
            if (resolved.isEmpty()) {
                continue;
            }
            Optional<SymbolTarget> target = targetFor(resolved.get(), selectedFilePath, selectedText, overlays);
            if (target.isEmpty() || !sameTarget(definition, target.get())) {
                continue;
            }
            Optional<TextRange> range = importDeclaration.getName().getRange()
                .map(nodeRange -> TextRanges.lastIdentifierRange(text, nodeRange.begin, nodeRange.end, identifier.name()));
            if (range.isEmpty()) {
                continue;
            }

            String key = sourceFile + ":" + range.get().location() + ":" + range.get().length();
            if (!seen.add(key)) {
                continue;
            }
            references.add(new SymbolTarget(sourceFile.toUri().toString(), range.get(), identifier.name(), "usage"));
            if (references.size() >= limit) {
                break;
            }
        }
        return references;
    }

    private Optional<SymbolTarget> referenceTarget(
        SimpleName candidate,
        SymbolTarget definition,
        CombinedTypeSolver typeSolver,
        List<Path> sourceRoots,
        Path selectedFilePath,
        String selectedText,
        Map<Path, String> overlays
    ) throws IOException {
        if ("type".equals(definition.kind())) {
            Optional<Node> parent = candidate.getParentNode();
            if (parent.isPresent() && parent.get() instanceof ClassOrInterfaceType classType && classType.getName() == candidate) {
                try {
                    ResolvedType resolvedType = classType.resolve();
                    if (resolvedType.isReferenceType()) {
                        Optional<Node> node = resolvedType.asReferenceType()
                            .getTypeDeclaration()
                            .flatMap(ResolvedDeclaration::toAst);
                        if (node.isPresent()) {
                            return targetFor(node.get(), selectedFilePath, selectedText, overlays);
                        }
                    }
                } catch (RuntimeException ignored) {
                    return Optional.empty();
                }
            }
        }
        return resolveTarget(candidate, typeSolver, sourceRoots, selectedFilePath, selectedText, overlays);
    }

    private boolean sameTarget(SymbolTarget lhs, SymbolTarget rhs) {
        return Objects.equals(lhs.url(), rhs.url())
            && Objects.equals(lhs.range(), rhs.range())
            && Objects.equals(lhs.kind(), rhs.kind())
            && Objects.equals(lhs.name(), rhs.name());
    }

    private Optional<SymbolTarget> resolveTarget(
        SimpleName name,
        CombinedTypeSolver typeSolver,
        List<Path> sourceRoots,
        Path selectedFilePath,
        String selectedText,
        Map<Path, String> overlays
    ) throws IOException {
        try {
            Optional<Node> resolvedNode = resolvedAstNode(name, typeSolver, sourceRoots);
            if (resolvedNode.isEmpty()) {
                return Optional.empty();
            }
            return targetFor(resolvedNode.get(), selectedFilePath, selectedText, overlays);
        } catch (UnsolvedSymbolException | UnsupportedOperationException | IllegalStateException ignored) {
            return Optional.empty();
        } catch (RuntimeException error) {
            return Optional.empty();
        }
    }

    private Optional<SymbolTarget> lexicalTarget(
        CompilationUnit unit,
        String sourceText,
        TextRange selectedRange,
        Path selectedFilePath,
        Map<Path, String> overlays
    ) throws IOException {
        Optional<NameExpr> expression = unit.findAll(NameExpr.class).stream()
            .filter(name -> name.getName().getRange()
                .map(range -> TextRanges.from(sourceText, range.begin, range.end))
                .map(range -> rangesTouch(range, selectedRange))
                .orElse(false))
            .findFirst();
        if (expression.isEmpty()) {
            return Optional.empty();
        }

        Optional<Node> declaration = lexicalValueDeclaration(expression.get());
        if (declaration.isEmpty()) {
            return Optional.empty();
        }
        return targetFor(declaration.get(), selectedFilePath, sourceText, overlays);
    }

    private Optional<SymbolTarget> importTarget(
        CompilationUnit unit,
        String sourceText,
        TextRange selectedRange,
        CombinedTypeSolver typeSolver,
        List<Path> sourceRoots,
        Path selectedFilePath,
        Map<Path, String> overlays
    ) throws IOException {
        Optional<ImportDeclaration> importDeclaration = unit.getImports().stream()
            .filter(declaration -> declaration.getRange()
                .map(range -> TextRanges.from(sourceText, range.begin, range.end))
                .map(range -> rangesTouch(range, selectedRange))
                .orElse(false))
            .findFirst();
        if (importDeclaration.isEmpty()) {
            return Optional.empty();
        }

        Optional<Node> resolved = resolveImport(importDeclaration.get(), typeSolver, sourceRoots);
        if (resolved.isEmpty()) {
            return Optional.empty();
        }
        return targetFor(resolved.get(), selectedFilePath, sourceText, overlays);
    }

    private Optional<Node> resolvedAstNode(SimpleName name, CombinedTypeSolver typeSolver, List<Path> sourceRoots) {
        Optional<Node> parent = name.getParentNode();
        if (parent.isEmpty()) {
            return Optional.empty();
        }

        Node node = parent.get();
        if (node instanceof MethodCallExpr methodCall && methodCall.getName() == name) {
            return methodCall.resolve().toAst();
        }
        if (node instanceof ObjectCreationExpr objectCreation && objectCreation.getType().getName() == name) {
            return resolveConstructor(objectCreation);
        }
        if (node instanceof ClassOrInterfaceType classType && classType.getName() == name) {
            Optional<ObjectCreationExpr> objectCreation = classType.findAncestor(ObjectCreationExpr.class);
            if (objectCreation.isPresent() && objectCreation.get().getType() == classType) {
                return resolveConstructor(objectCreation.get());
            }
            ResolvedType resolvedType = classType.resolve();
            if (resolvedType.isReferenceType()) {
                ResolvedReferenceType referenceType = resolvedType.asReferenceType();
                return referenceType.getTypeDeclaration().flatMap(ResolvedDeclaration::toAst);
            }
            return Optional.empty();
        }
        if (node instanceof NameExpr nameExpr && nameExpr.getName() == name) {
            return resolvedNameExpressionAst(nameExpr, typeSolver)
                .or(() -> lexicalValueDeclaration(nameExpr));
        }
        if (node instanceof FieldAccessExpr fieldAccess && fieldAccess.getName() == name) {
            return astForValueDeclaration(JavaParserFacade.get(typeSolver).solve(fieldAccess).getCorrespondingDeclaration());
        }
        if (node instanceof MethodReferenceExpr methodReference && methodReference.getIdentifier().equals(name.asString())) {
            return methodReference.resolve().toAst();
        }
        if (node instanceof Name qualifiedName && qualifiedName.getIdentifier().equals(name.asString())) {
            return resolveQualifiedName(qualifiedName, typeSolver, sourceRoots);
        }
        if (node instanceof ImportDeclaration importDeclaration) {
            return resolveImport(importDeclaration, typeSolver, sourceRoots);
        }

        return Optional.empty();
    }

    private Optional<Node> astForValueDeclaration(ResolvedValueDeclaration declaration) {
        if (declaration.isField()) {
            return declaration.asField().toAst();
        }
        if (declaration.isParameter()) {
            return declaration.asParameter().toAst();
        }
        return declaration.toAst();
    }

    private Optional<Node> resolveConstructor(ObjectCreationExpr objectCreation) {
        ResolvedConstructorDeclaration constructor = objectCreation.resolve();
        Optional<Node> constructorAst = constructor.toAst();
        if (constructorAst.isPresent() && constructorAst.get() instanceof ConstructorDeclaration) {
            return constructorAst;
        }
        Optional<Node> matchingConstructor = matchingConstructorAst(constructor);
        if (matchingConstructor.isPresent()) {
            return matchingConstructor;
        }
        return objectCreation.getArguments().isEmpty() ? constructor.declaringType().toAst() : Optional.empty();
    }

    private Optional<Node> resolvedNameExpressionAst(NameExpr expression, CombinedTypeSolver typeSolver) {
        try {
            return astForValueDeclaration(JavaParserFacade.get(typeSolver).solve(expression).getCorrespondingDeclaration());
        } catch (RuntimeException ignored) {
            return Optional.empty();
        }
    }

    private Optional<Node> matchingConstructorAst(ResolvedConstructorDeclaration constructor) {
        Optional<Node> typeAst = constructor.declaringType().toAst();
        if (typeAst.isEmpty() || !(typeAst.get() instanceof TypeDeclaration<?> typeDeclaration)) {
            return Optional.empty();
        }
        return typeDeclaration.getConstructors().stream()
            .filter(declaration -> declaration.getNameAsString().equals(constructor.getName()))
            .filter(declaration -> declaration.getParameters().size() == constructor.getNumberOfParams())
            .filter(declaration -> constructorParametersMatch(declaration, constructor))
            .map(declaration -> (Node) declaration)
            .findFirst();
    }

    private Optional<Node> lexicalValueDeclaration(NameExpr expression) {
        String name = expression.getNameAsString();
        Optional<CallableDeclaration<?>> callable = callableAncestor(expression);
        if (callable.isPresent()) {
            for (Parameter parameter : callable.get().getParameters()) {
                if (parameter.getNameAsString().equals(name)) {
                    return Optional.of(parameter);
                }
            }
        }

        int usageBegin = expression.getRange()
            .map(range -> range.begin.line * 1_000_000 + range.begin.column)
            .orElse(Integer.MAX_VALUE);
        Node scope = callable
            .map(callableDeclaration -> (Node) callableDeclaration)
            .orElseGet(() -> expression.findCompilationUnit().map(unit -> (Node) unit).orElse(expression));
        return scope.findAll(VariableDeclarator.class).stream()
            .filter(variable -> variable.getNameAsString().equals(name))
            .filter(variable -> variable.getRange()
                .map(range -> range.begin.line * 1_000_000 + range.begin.column < usageBegin)
                .orElse(false))
            .max(Comparator.comparingInt(variable -> variable.getRange()
                .map(range -> range.begin.line * 1_000_000 + range.begin.column)
                .orElse(0)))
            .map(variable -> (Node) variable);
    }

    private Optional<CallableDeclaration<?>> callableAncestor(Node node) {
        Optional<Node> parent = node.getParentNode();
        while (parent.isPresent()) {
            Node current = parent.get();
            if (current instanceof CallableDeclaration<?> callable) {
                return Optional.of(callable);
            }
            parent = current.getParentNode();
        }
        return Optional.empty();
    }

    private boolean constructorParametersMatch(ConstructorDeclaration declaration, ResolvedConstructorDeclaration constructor) {
        for (int index = 0; index < declaration.getParameters().size(); index += 1) {
            String declaredType = declaration.getParameter(index).getType().resolve().describe();
            String resolvedType = constructor.getParam(index).getType().describe();
            if (!declaredType.equals(resolvedType)) {
                return false;
            }
        }
        return true;
    }

    private Optional<Node> resolveQualifiedName(Name name, CombinedTypeSolver typeSolver, List<Path> sourceRoots) {
        return importAncestor(name)
            .flatMap(importDeclaration -> resolveImport(importDeclaration, typeSolver, sourceRoots));
    }

    private Optional<ImportDeclaration> importAncestor(Node node) {
        Optional<Node> parent = node.getParentNode();
        while (parent.isPresent()) {
            Node current = parent.get();
            if (current instanceof ImportDeclaration importDeclaration) {
                return Optional.of(importDeclaration);
            }
            parent = current.getParentNode();
        }
        return Optional.empty();
    }

    private Optional<Node> resolveImport(ImportDeclaration importDeclaration, CombinedTypeSolver typeSolver, List<Path> sourceRoots) {
        if (importDeclaration.isAsterisk()) {
            return Optional.empty();
        }
        String qualifiedName = importDeclaration.getNameAsString();
        Optional<Node> ast = typeSolver.solveType(qualifiedName).toAst();
        return ast.isPresent() ? ast : typeDeclarationAtSourcePath(qualifiedName, sourceRoots);
    }

    private Optional<Node> typeDeclarationAtSourcePath(String qualifiedName, List<Path> sourceRoots) {
        String relativePath = qualifiedName.replace('.', '/') + ".java";
        String simpleName = qualifiedName.substring(qualifiedName.lastIndexOf('.') + 1);
        for (Path sourceRoot : sourceRoots) {
            Path sourcePath = sourceRoot.resolve(relativePath).toAbsolutePath().normalize();
            if (!Files.isRegularFile(sourcePath)) {
                continue;
            }
            try {
                String text = Files.readString(sourcePath, StandardCharsets.UTF_8);
                Optional<CompilationUnit> unit = new JavaParser().parse(text).getResult();
                if (unit.isEmpty()) {
                    continue;
                }
                unit.get().setStorage(sourcePath);
                Optional<Node> declaration = unit.get().getTypes().stream()
                    .filter(type -> type.getNameAsString().equals(simpleName))
                    .map(type -> (Node) type)
                    .findFirst();
                if (declaration.isPresent()) {
                    return declaration;
                }
            } catch (IOException ignored) {
            }
        }
        return Optional.empty();
    }

    private Optional<SymbolTarget> targetFor(
        Node node,
        Path selectedFilePath,
        String selectedText,
        Map<Path, String> overlays
    ) throws IOException {
        Node targetNode = declarationNameNode(node).orElse(node);
        Path path = pathFor(targetNode).orElseGet(() -> pathFor(node).orElse(selectedFilePath));
        path = path.toAbsolutePath().normalize();
        String text = textFor(path, selectedFilePath, selectedText, overlays);

        Optional<com.github.javaparser.Range> range = targetNode.getRange();
        if (range.isEmpty()) {
            return Optional.empty();
        }

        TextRange textRange = TextRanges.from(text, range.get().begin, range.get().end);
        String name = nameFor(targetNode);
        if (name == null || name.isBlank()) {
            return Optional.empty();
        }

        return Optional.of(new SymbolTarget(path.toUri().toString(), textRange, name, kindFor(node)));
    }

    private Optional<Node> declarationNameNode(Node node) {
        if (node instanceof NodeWithSimpleName<?> named) {
            return Optional.of(named.getName());
        }
        if (node instanceof VariableDeclarator variable) {
            return Optional.of(variable.getName());
        }
        if (node instanceof EnumConstantDeclaration enumConstant) {
            return Optional.of(enumConstant.getName());
        }
        if (node instanceof ImportDeclaration importDeclaration) {
            return Optional.of(importDeclaration.getName());
        }
        return Optional.empty();
    }

    private Optional<Path> pathFor(Node node) {
        return node.findCompilationUnit()
            .flatMap(CompilationUnit::getStorage)
            .map(CompilationUnit.Storage::getPath)
            .map(path -> path.toAbsolutePath().normalize());
    }

    private String textFor(
        Path path,
        Path selectedFilePath,
        String selectedText,
        Map<Path, String> overlays
    ) throws IOException {
        if (path.equals(selectedFilePath)) {
            return selectedText;
        }
        String overlay = overlays.get(path);
        if (overlay != null) {
            return overlay;
        }
        return Files.readString(path, StandardCharsets.UTF_8);
    }

    private String nameFor(Node node) {
        if (node instanceof SimpleName simpleName) {
            return simpleName.asString();
        }
        if (node instanceof NodeWithSimpleName<?> named) {
            return named.getNameAsString();
        }
        if (node instanceof NodeWithName<?> named) {
            return named.getNameAsString();
        }
        return null;
    }

    private String kindFor(Node node) {
        if (node instanceof MethodDeclaration) {
            return "method";
        }
        if (node instanceof ConstructorDeclaration) {
            return "constructor";
        }
        if (node instanceof FieldDeclaration || node instanceof EnumConstantDeclaration) {
            return "field";
        }
        if (node instanceof VariableDeclarator) {
            return "variable";
        }
        if (node instanceof Parameter) {
            return "parameter";
        }
        if (node instanceof TypeDeclaration<?>) {
            return "type";
        }
        return "type";
    }

    private boolean rangesTouch(TextRange lhs, TextRange rhs) {
        int lhsEnd = lhs.location() + lhs.length();
        int rhsEnd = rhs.location() + rhs.length();
        return lhs.location() <= rhsEnd && rhs.location() <= lhsEnd;
    }

    private record ResolverRuntime(JavaParser parser, CombinedTypeSolver typeSolver) {}

    private record Identifier(String name, TextRange range) {
        static Identifier at(String text, int utf16Offset) {
            if (text == null || text.isEmpty()) {
                return null;
            }
            int offset = Math.max(0, Math.min(utf16Offset, text.length()));
            if (offset == text.length()) {
                offset -= 1;
            }
            if (!isIdentifierCharacter(text.charAt(offset)) && offset > 0 && isIdentifierCharacter(text.charAt(offset - 1))) {
                offset -= 1;
            }
            if (!isIdentifierCharacter(text.charAt(offset))) {
                return null;
            }

            int start = offset;
            while (start > 0 && isIdentifierCharacter(text.charAt(start - 1))) {
                start -= 1;
            }
            int end = offset + 1;
            while (end < text.length() && isIdentifierCharacter(text.charAt(end))) {
                end += 1;
            }
            return new Identifier(text.substring(start, end), new TextRange(start, end - start));
        }

        private static boolean isIdentifierCharacter(char character) {
            return Character.isLetterOrDigit(character) || character == '_' || character == '$';
        }
    }

    private static final class TextRanges {
        static TextRange from(String text, Position begin, Position end) {
            int location = offset(text, begin);
            int endLocation = offset(text, end);
            return new TextRange(location, Math.max(0, endLocation - location + 1));
        }

        static TextRange lastIdentifierRange(String text, Position begin, Position end, String identifier) {
            TextRange fullRange = from(text, begin, end);
            int start = fullRange.location();
            int length = fullRange.length();
            int relativeLocation = text.substring(start, Math.min(text.length(), start + length)).lastIndexOf(identifier);
            if (relativeLocation < 0) {
                return fullRange;
            }
            return new TextRange(start + relativeLocation, identifier.length());
        }

        private static int offset(String text, Position position) {
            int line = Math.max(1, position.line);
            int column = Math.max(1, position.column);
            int currentLine = 1;
            int index = 0;
            while (index < text.length() && currentLine < line) {
                if (text.charAt(index) == '\n') {
                    currentLine += 1;
                }
                index += 1;
            }
            return Math.min(text.length(), index + column - 1);
        }
    }
}
