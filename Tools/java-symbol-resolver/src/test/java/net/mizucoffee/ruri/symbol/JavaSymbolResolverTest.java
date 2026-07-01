package net.mizucoffee.ruri.symbol;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;

import static org.junit.jupiter.api.Assertions.*;

final class JavaSymbolResolverTest {
    @TempDir
    Path root;

    @Test
    void resolvesImportedClassDefinitionFromSourceRoot() throws Exception {
        Path sourceRoot = Files.createDirectories(root.resolve("src/main/java"));
        Path app = Files.createDirectories(sourceRoot.resolve("app"));
        Path service = Files.createDirectories(sourceRoot.resolve("service"));
        Path source = app.resolve("Controller.java");
        Path target = service.resolve("UserService.java");
        Path other = app.resolve("UserService.java");
        String sourceText = """
            package app;
            import service.UserService;
            class Controller { UserService service; }
            """;
        String targetText = "package service;\npublic class UserService {}\n";
        Files.writeString(source, sourceText, StandardCharsets.UTF_8);
        Files.writeString(target, targetText, StandardCharsets.UTF_8);
        Files.writeString(other, "package app;\nclass UserService {}\n", StandardCharsets.UTF_8);

        ResolverResponse response = resolve(source, sourceText, sourceText.lastIndexOf("UserService"), List.of(sourceRoot));
        ResolverResponse importResponse = resolve(source, sourceText, sourceText.indexOf("UserService"), List.of(sourceRoot));

        assertEquals("implementation", response.resolutionKind(), response.toString());
        assertNotNull(response.target());
        assertEquals(target.toUri().toString(), response.target().url());
        assertEquals("implementation", importResponse.resolutionKind(), importResponse.toString());
        assertNotNull(importResponse.target());
        assertEquals(target.toUri().toString(), importResponse.target().url());
    }

    @Test
    void resolvesExactOverloadedMethod() throws Exception {
        Path source = root.resolve("Source.java");
        String sourceText = """
            class Source {
                void run() {}
                void run(String value) {}
                void run(int count, boolean enabled) {}
                void call() { run("value"); }
            }
            """;
        Files.writeString(source, sourceText, StandardCharsets.UTF_8);

        ResolverResponse response = resolve(source, sourceText, sourceText.lastIndexOf("run(\"value\")"), List.of(root));

        assertEquals("implementation", response.resolutionKind(), response.toString());
        assertNotNull(response.target());
        assertEquals("method", response.target().kind());
        assertEquals(sourceText.indexOf("run(String"), response.target().range().location());
    }

    @Test
    void resolvesExactOverloadedConstructor() throws Exception {
        Path source = root.resolve("Source.java");
        String sourceText = """
            class Target {
                Target() {}
                Target(String value) {}
            }
            class Source {
                void call() { new Target("value"); }
            }
            """;
        Files.writeString(source, sourceText, StandardCharsets.UTF_8);

        ResolverResponse response = resolve(source, sourceText, sourceText.indexOf("Target(\"value\")"), List.of(root));

        assertEquals("implementation", response.resolutionKind(), response.toString());
        assertNotNull(response.target());
        assertEquals("constructor", response.target().kind());
        assertEquals(sourceText.indexOf("Target(String"), response.target().range().location());
    }

    @Test
    void resolvesLocalVariableInsteadOfFieldWithSameName() throws Exception {
        Path source = root.resolve("Source.java");
        String sourceText = """
            class Source {
                String value;
                void call() {
                    String value = "";
                    System.out.println(value);
                }
            }
            """;
        Files.writeString(source, sourceText, StandardCharsets.UTF_8);

        ResolverResponse response = resolve(source, sourceText, sourceText.lastIndexOf("value"), List.of(root));

        assertEquals("implementation", response.resolutionKind(), response.toString());
        assertNotNull(response.target());
        assertEquals("variable", response.target().kind());
        assertEquals(sourceText.indexOf("value ="), response.target().range().location());
    }

    @Test
    void returnsReferencesForDefinitionClick() throws Exception {
        Path source = root.resolve("Source.java");
        String sourceText = "class Target {}\nclass Source { Target target; }\n";
        Files.writeString(source, sourceText, StandardCharsets.UTF_8);

        ResolverResponse response = resolveReferences(source, sourceText, sourceText.indexOf("Target"), List.of(root), List.of(source));

        assertEquals("references", response.resolutionKind(), response.toString());
        assertNull(response.target());
        assertEquals(1, response.targets().size());
        assertEquals("usage", response.targets().get(0).kind());
        assertEquals(sourceText.lastIndexOf("Target"), response.targets().get(0).range().location());
    }

    @Test
    void returnsNilForDefinitionClickWithoutReferences() throws Exception {
        Path source = root.resolve("Source.java");
        String sourceText = "class Target {}\n";
        Files.writeString(source, sourceText, StandardCharsets.UTF_8);

        ResolverResponse response = resolveReferences(source, sourceText, sourceText.indexOf("Target"), List.of(root), List.of(source));

        assertNull(response.resolutionKind());
        assertNull(response.target());
        assertTrue(response.targets().isEmpty());
    }

    @Test
    void returnsOnlyExactOverloadedMethodReferences() throws Exception {
        Path source = root.resolve("Source.java");
        String sourceText = """
            class Source {
                void run() {}
                void run(String value) {}
                void call() {
                    run();
                    run("value");
                }
            }
            """;
        Files.writeString(source, sourceText, StandardCharsets.UTF_8);

        ResolverResponse response = resolveReferences(source, sourceText, sourceText.indexOf("run(String"), List.of(root), List.of(source));

        assertEquals("references", response.resolutionKind(), response.toString());
        assertEquals(1, response.targets().size());
        assertEquals(sourceText.lastIndexOf("run(\"value\")"), response.targets().get(0).range().location());
    }

    @Test
    void classDefinitionReferencesIncludeObjectCreationType() throws Exception {
        Path source = root.resolve("Source.java");
        String sourceText = """
            class Target {
                Target(String value) {}
            }
            class Source {
                void call() { new Target("value"); }
            }
            """;
        Files.writeString(source, sourceText, StandardCharsets.UTF_8);

        ResolverResponse response = resolveReferences(source, sourceText, sourceText.indexOf("Target"), List.of(root), List.of(source));

        assertEquals("references", response.resolutionKind(), response.toString());
        assertEquals(1, response.targets().size());
        assertEquals(sourceText.lastIndexOf("Target(\"value\")"), response.targets().get(0).range().location());
    }

    @Test
    void constructorDefinitionReferencesOnlyMatchingConstructorCalls() throws Exception {
        Path source = root.resolve("Source.java");
        String sourceText = """
            class Target {
                Target() {}
                Target(String value) {}
            }
            class Source {
                void call() {
                    new Target();
                    new Target("value");
                }
            }
            """;
        Files.writeString(source, sourceText, StandardCharsets.UTF_8);

        ResolverResponse response = resolveReferences(source, sourceText, sourceText.indexOf("Target(String"), List.of(root), List.of(source));

        assertEquals("references", response.resolutionKind(), response.toString());
        assertEquals(1, response.targets().size());
        assertEquals(sourceText.lastIndexOf("Target(\"value\")"), response.targets().get(0).range().location());
    }

    @Test
    void returnsNilForUnresolvedUsage() throws Exception {
        Path source = root.resolve("Source.java");
        String sourceText = "class Source { Missing missing; }\n";
        Files.writeString(source, sourceText, StandardCharsets.UTF_8);

        ResolverResponse response = resolve(source, sourceText, sourceText.indexOf("Missing"), List.of(root));

        assertNull(response.resolutionKind());
        assertNull(response.target());
        assertTrue(response.targets().isEmpty());
    }

    @Test
    void hoverRequiresStrictResolution() throws Exception {
        Path source = root.resolve("Source.java");
        Path target = root.resolve("Target.java");
        String sourceText = "class Source { Target target; Missing missing; }\n";
        Files.writeString(source, sourceText, StandardCharsets.UTF_8);
        Files.writeString(target, "class Target {}\n", StandardCharsets.UTF_8);

        ResolverResponse resolved = new JavaSymbolResolver().resolve(new ResolverRequest(
            "hover",
            root.toString(),
            source.toString(),
            sourceText,
            sourceText.indexOf("Target"),
            List.of(),
            List.of(root.toString()),
            List.of(),
            List.of(),
            null
        ));
        ResolverResponse unresolved = new JavaSymbolResolver().resolve(new ResolverRequest(
            "hover",
            root.toString(),
            source.toString(),
            sourceText,
            sourceText.indexOf("Missing"),
            List.of(),
            List.of(root.toString()),
            List.of(),
            List.of(),
            null
        ));

        assertNotNull(resolved.hoverRange());
        assertNull(unresolved.hoverRange());
    }

    @Test
    void hoverReturnsDefinitionRangeWhenDefinitionHasReferences() throws Exception {
        Path source = root.resolve("Source.java");
        String sourceText = "class Target {}\nclass Source { Target target; }\n";
        Files.writeString(source, sourceText, StandardCharsets.UTF_8);

        ResolverResponse response = new JavaSymbolResolver().resolve(new ResolverRequest(
            "hover",
            root.toString(),
            source.toString(),
            sourceText,
            sourceText.indexOf("Target"),
            List.of(),
            List.of(root.toString()),
            List.of(source.toString()),
            List.of(),
            1
        ));

        assertNotNull(response.hoverRange());
        assertEquals(sourceText.indexOf("Target"), response.hoverRange().location());
    }

    private ResolverResponse resolve(Path source, String sourceText, int offset, List<Path> sourceRoots) throws Exception {
        return new JavaSymbolResolver().resolve(new ResolverRequest(
            "resolve",
            root.toString(),
            source.toString(),
            sourceText,
            offset,
            List.of(),
            sourceRoots.stream().map(Path::toString).toList(),
            List.of(),
            List.of(),
            null
        ));
    }

    private ResolverResponse resolveReferences(
        Path source,
        String sourceText,
        int offset,
        List<Path> sourceRoots,
        List<Path> sourceFiles
    ) throws Exception {
        return new JavaSymbolResolver().resolve(new ResolverRequest(
            "resolve",
            root.toString(),
            source.toString(),
            sourceText,
            offset,
            List.of(),
            sourceRoots.stream().map(Path::toString).toList(),
            sourceFiles.stream().map(Path::toString).toList(),
            List.of(),
            null
        ));
    }
}
