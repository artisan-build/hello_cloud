package build.artisan.hellocloud;

import io.javalin.Javalin;
import java.io.IOException;
import java.io.InputStream;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;

/**
 * Two routes, served by Javalin. Laravel Cloud runs this because the branch
 * carries a go.mod at its root, so Cloud picked its Go runtime and starts
 * whatever executable it finds at ./app -- which here is a self-extracting
 * launcher wrapped around a jlink runtime image and this jar.
 *
 * <p>The template and the card are read out of the jar at class-init time, not
 * off the filesystem: Cloud's filesystem is ephemeral and holds none of this
 * repo.
 */
public final class App {
    private static final String LANGUAGE = "Java";
    private static final String BRANCH = "java";
    private static final String REPO_URL = "https://github.com/artisan-build/hello_cloud";

    private static final String TEMPLATE = text("/page.html");
    private static final String INDEX_URL = text("/index-url.txt").trim();
    private static final byte[] OG_PNG = bytes("/og.png");

    private App() {}

    public static void main(String[] args) {
        int port = Integer.parseInt(
                System.getenv().getOrDefault("PORT", "3000"));

        Javalin app = Javalin.create(cfg -> cfg.showJavalinBanner = false);

        app.get("/", ctx -> {
            ctx.contentType("text/html; charset=utf-8");
            ctx.result(render(host(ctx.header("Host"))));
        });

        app.get("/og.png", ctx -> {
            ctx.contentType("image/png");
            ctx.header("Cache-Control", "public, max-age=3600");
            ctx.result(OG_PNG);
        });

        // "::" is the IPv6 wildcard, which on Linux is dual-stack: Laravel
        // Cloud's per-instance nginx proxies to 127.0.0.1:$PORT over an
        // IPv6-only network, so one socket has to answer both.
        app.start("::", port);
    }

    private static String host(String header) {
        return header == null || header.isBlank() ? "localhost" : header;
    }

    /**
     * Fills the shared template's seven placeholders. Keep in step with main.go.
     * The absolute URLs come from the request's Host header with the scheme
     * hard-coded to https: Cloud terminates TLS upstream and then sends
     * X-Forwarded-Proto: http on an https request, so that header is unusable.
     */
    private static String render(String host) {
        String base = "https://" + host;
        return TEMPLATE
                .replace("{{LANGUAGE}}", LANGUAGE)
                .replace("{{BRANCH}}", BRANCH)
                .replace("{{BRANCH_URL}}", REPO_URL + "/tree/" + BRANCH)
                .replace("{{OG_IMAGE}}", base + "/og.png")
                .replace("{{PAGE_URL}}", base + "/")
                .replace("{{INDEX_URL}}", INDEX_URL)
                .replace("{{EXTRA}}", "");
    }

    private static String text(String resource) {
        return new String(bytes(resource), StandardCharsets.UTF_8);
    }

    private static byte[] bytes(String resource) {
        try (InputStream in = App.class.getResourceAsStream(resource)) {
            if (in == null) {
                throw new IllegalStateException("missing resource " + resource);
            }
            return in.readAllBytes();
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }
}
