package build.artisan.hellocloud

import io.ktor.http.ContentType
import io.ktor.http.HttpHeaders
import io.ktor.http.withCharset
import io.ktor.server.cio.CIO
import io.ktor.server.engine.embeddedServer
import io.ktor.server.request.header
import io.ktor.server.response.respondBytes
import io.ktor.server.response.respondText
import io.ktor.server.routing.get
import io.ktor.server.routing.routing

/**
 * Two routes, served by Ktor on its CIO engine. Laravel Cloud runs this because
 * the branch carries a go.mod at its root, so Cloud picked its Go runtime and
 * starts whatever executable it finds at ./app -- which here is a
 * self-extracting launcher wrapped around a jlink runtime image and this jar.
 */
private const val LANGUAGE = "Kotlin"
private const val BRANCH = "kotlin"
private const val REPO_URL = "https://github.com/artisan-build/hello_cloud"

// Read out of the jar, not off the filesystem: Cloud's filesystem is ephemeral
// and holds none of this repo.
private val TEMPLATE = resource("/page.html").decodeToString()
private val INDEX_URL = resource("/index-url.txt").decodeToString().trim()
private val OG_PNG = resource("/og.png")

private fun resource(name: String): ByteArray =
    checkNotNull(object {}.javaClass.getResourceAsStream(name)) { "missing resource $name" }
        .use { it.readBytes() }

fun main() {
    val port = (System.getenv("PORT") ?: "3000").toInt()

    // "::" is the IPv6 wildcard, which on Linux is dual-stack: Cloud's
    // per-instance nginx proxies to 127.0.0.1:$PORT over an IPv6-only network,
    // so one socket has to answer both.
    embeddedServer(CIO, port = port, host = "::") {
        routing {
            get("/") {
                val host = call.request.header(HttpHeaders.Host) ?: "localhost"
                call.respondText(
                    render(host),
                    ContentType.Text.Html.withCharset(Charsets.UTF_8),
                )
            }
            get("/og.png") {
                call.response.headers.append(HttpHeaders.CacheControl, "public, max-age=3600")
                call.respondBytes(OG_PNG, ContentType.Image.PNG)
            }
        }
    }.start(wait = true)
}

/**
 * Fills the shared template's seven placeholders. Keep in step with main.go.
 * The absolute URLs come from the request's Host header with the scheme
 * hard-coded to https: Cloud terminates TLS upstream and then sends
 * X-Forwarded-Proto: http on an https request, so that header is unusable.
 */
private fun render(host: String): String {
    val base = "https://$host"
    return TEMPLATE
        .replace("{{LANGUAGE}}", LANGUAGE)
        .replace("{{BRANCH}}", BRANCH)
        .replace("{{BRANCH_URL}}", "$REPO_URL/tree/$BRANCH")
        .replace("{{OG_IMAGE}}", "$base/og.png")
        .replace("{{PAGE_URL}}", "$base/")
        .replace("{{INDEX_URL}}", INDEX_URL)
        .replace("{{EXTRA}}", "")
}
