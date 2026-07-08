package net.mizucoffee.ruri.symbol;

import com.google.gson.Gson;
import com.google.gson.JsonSyntaxException;

import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.nio.charset.StandardCharsets;

public final class Main {
    // Swift側(JavaSymbolResolverClient.outOfMemoryExitCode)と対応する契約値。
    static final int EXIT_CODE_OUT_OF_MEMORY = 3;

    @FunctionalInterface
    interface Resolver {
        ResolverResponse resolve(ResolverRequest request) throws Exception;
    }

    private final Gson gson = new Gson();
    private final Resolver resolver;

    Main() {
        this(new JavaSymbolResolver()::resolve);
    }

    Main(Resolver resolver) {
        this.resolver = resolver;
    }

    public static void main(String[] args) throws Exception {
        System.exit(new Main().run());
    }

    int run() throws Exception {
        try (var reader = new BufferedReader(new InputStreamReader(System.in, StandardCharsets.UTF_8));
             var writer = new BufferedWriter(new OutputStreamWriter(System.out, StandardCharsets.UTF_8))) {
            String line;
            while ((line = reader.readLine()) != null) {
                HandleResult result = handle(line);
                writer.write(result.json());
                writer.newLine();
                writer.flush();
                if (result.exitCode() != null) {
                    return result.exitCode();
                }
            }
        }
        return 0;
    }

    HandleResult handle(String line) {
        String id = "";
        try {
            RequestEnvelope envelope = gson.fromJson(line, RequestEnvelope.class);
            id = envelope.id == null ? "" : envelope.id;
            ResolverResponse response = resolver.resolve(envelope.payload);
            return new HandleResult(gson.toJson(new ResponseEnvelope(id, response, null)), null);
        } catch (JsonSyntaxException error) {
            return new HandleResult(
                gson.toJson(new ResponseEnvelope(id, null, "Invalid request JSON: " + error.getMessage())),
                null
            );
        } catch (OutOfMemoryError error) {
            // ヒープが汚染された状態で生き続けると後続要求も失敗し続けるため、
            // このエラー応答を返した後にプロセスを終了してSwift側の再起動に任せる。
            String message = "Java symbol resolver ran out of memory while indexing symbols.";
            return new HandleResult(
                gson.toJson(new ResponseEnvelope(id, null, message)),
                EXIT_CODE_OUT_OF_MEMORY
            );
        } catch (Throwable error) {
            // StackOverflowErrorなどのErrorでもJVMを落とさず、1要求分のエラー応答
            // として返す(プロセスが死ぬと全pending要求が失敗する)。
            String message = error.getMessage();
            if (message == null || message.isBlank()) {
                message = error.getClass().getSimpleName();
            }
            return new HandleResult(gson.toJson(new ResponseEnvelope(id, null, message)), null);
        }
    }

    record HandleResult(String json, Integer exitCode) {}

    private record RequestEnvelope(String id, ResolverRequest payload) {}

    private record ResponseEnvelope(String id, ResolverResponse payload, String error) {}
}
