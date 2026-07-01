package net.mizucoffee.ruri.symbol;

import java.util.List;

record ResolverRequest(
    String command,
    String projectPath,
    String filePath,
    String text,
    int utf16Offset,
    List<OpenDocument> openDocuments,
    List<String> sourceRoots,
    List<String> sourceFiles,
    List<String> classpath,
    Integer referenceLimit
) {}

record OpenDocument(String path, String text) {}

record ResolverResponse(
    String resolutionKind,
    SymbolTarget target,
    List<SymbolTarget> targets,
    TextRange hoverRange,
    Boolean needsReferenceSearch,
    List<String> diagnostics
) {}

record SymbolTarget(String url, TextRange range, String name, String kind) {}

record TextRange(int location, int length) {}
