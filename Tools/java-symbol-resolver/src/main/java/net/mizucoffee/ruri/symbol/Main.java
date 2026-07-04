package net.mizucoffee.ruri.symbol;

import com.google.gson.Gson;
import com.google.gson.JsonSyntaxException;

import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.nio.charset.StandardCharsets;

public final class Main {
    private final Gson gson = new Gson();
    private final JavaSymbolResolver resolver = new JavaSymbolResolver();

    public static void main(String[] args) throws Exception {
        new Main().run();
    }

    private void run() throws Exception {
        try (var reader = new BufferedReader(new InputStreamReader(System.in, StandardCharsets.UTF_8));
             var writer = new BufferedWriter(new OutputStreamWriter(System.out, StandardCharsets.UTF_8))) {
            String line;
            while ((line = reader.readLine()) != null) {
                writer.write(handle(line));
                writer.newLine();
                writer.flush();
            }
        }
    }

    private String handle(String line) {
        String id = "";
        try {
            RequestEnvelope envelope = gson.fromJson(line, RequestEnvelope.class);
            id = envelope.id == null ? "" : envelope.id;
            ResolverResponse response = resolver.resolve(envelope.payload);
            return gson.toJson(new ResponseEnvelope(id, response, null));
        } catch (JsonSyntaxException error) {
            return gson.toJson(new ResponseEnvelope(id, null, "Invalid request JSON: " + error.getMessage()));
        } catch (Throwable error) {
            // StackOverflowError/OutOfMemoryErrorなどのErrorでもJVMを落とさず、
            // 1要求分のエラー応答として返す(プロセスが死ぬと全pending要求が失敗する)。
            String message = error.getMessage();
            if (message == null || message.isBlank()) {
                message = error.getClass().getSimpleName();
            }
            return gson.toJson(new ResponseEnvelope(id, null, message));
        }
    }

    private record RequestEnvelope(String id, ResolverRequest payload) {}

    private record ResponseEnvelope(String id, ResolverResponse payload, String error) {}
}
