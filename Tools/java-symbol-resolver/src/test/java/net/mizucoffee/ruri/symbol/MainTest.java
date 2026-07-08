package net.mizucoffee.ruri.symbol;

import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import org.junit.jupiter.api.Test;

import java.util.List;

import static org.junit.jupiter.api.Assertions.*;

final class MainTest {
    private static final String REQUEST_LINE = """
        {"id":"request-1","payload":{"command":"resolve","projectPath":"/tmp/project",\
        "filePath":"/tmp/project/Main.java","text":"class Main {}","utf16Offset":6,\
        "openDocuments":[],"sourceRoots":[],"sourceFiles":[],"classpath":[]}}""";

    @Test
    void handleReturnsErrorEnvelopeAndOutOfMemoryExitCode() {
        Main main = new Main(request -> {
            throw new OutOfMemoryError("Java heap space");
        });

        Main.HandleResult result = main.handle(REQUEST_LINE);

        JsonObject envelope = JsonParser.parseString(result.json()).getAsJsonObject();
        assertEquals("request-1", envelope.get("id").getAsString());
        assertTrue(envelope.get("error").getAsString().contains("out of memory"), result.json());
        assertEquals(Main.EXIT_CODE_OUT_OF_MEMORY, result.exitCode());
    }

    @Test
    void handleReturnsErrorEnvelopeWithoutExitForOrdinaryFailures() {
        Main main = new Main(request -> {
            throw new RuntimeException("boom");
        });

        Main.HandleResult result = main.handle(REQUEST_LINE);

        JsonObject envelope = JsonParser.parseString(result.json()).getAsJsonObject();
        assertEquals("request-1", envelope.get("id").getAsString());
        assertEquals("boom", envelope.get("error").getAsString());
        assertNull(result.exitCode());
    }

    @Test
    void handleReturnsInvalidJsonEnvelopeWithoutExit() {
        Main main = new Main(request -> new ResolverResponse(null, null, List.of(), null, false, List.of()));

        Main.HandleResult result = main.handle("this line is not json");

        JsonObject envelope = JsonParser.parseString(result.json()).getAsJsonObject();
        assertTrue(envelope.get("error").getAsString().startsWith("Invalid request JSON"), result.json());
        assertNull(result.exitCode());
    }
}
