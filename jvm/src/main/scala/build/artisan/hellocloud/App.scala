package build.artisan.hellocloud

/**
 * Two routes, served by cask (which runs on Undertow). Laravel Cloud runs this
 * because the branch carries a go.mod at its root, so Cloud picked its Go
 * runtime and starts whatever executable it finds at ./app -- which here is a
 * self-extracting launcher wrapped around a jlink runtime image and this jar.
 */
object App extends cask.MainRoutes:

  // "::" is the IPv6 wildcard, which on Linux is dual-stack: Cloud's
  // per-instance nginx proxies to 127.0.0.1:$PORT over an IPv6-only network,
  // so one socket has to answer both.
  override def host: String = "::"
  override def port: Int = sys.env.getOrElse("PORT", "3000").toInt

  private val Language = "Scala"
  private val Branch = "scala"
  private val RepoUrl = "https://github.com/artisan-build/hello_cloud"

  // Read out of the jar, not off the filesystem: Cloud's filesystem is
  // ephemeral and holds none of this repo.
  private val Template = String(resource("/page.html"), "UTF-8")
  private val IndexUrl = String(resource("/index-url.txt"), "UTF-8").trim
  private val OgPng = resource("/og.png")

  @cask.get("/")
  def index(request: cask.Request) =
    cask.Response(
      render(hostOf(request)),
      headers = Seq("Content-Type" -> "text/html; charset=utf-8")
    )

  @cask.get("/og.png")
  def ogPng() =
    cask.Response(
      OgPng,
      headers = Seq("Content-Type" -> "image/png", "Cache-Control" -> "public, max-age=3600")
    )

  private def hostOf(request: cask.Request): String =
    request.headers.get("host").flatMap(_.headOption).getOrElse("localhost")

  /**
   * Fills the shared template's seven placeholders. Keep in step with main.go.
   * The absolute URLs come from the request's Host header with the scheme
   * hard-coded to https: Cloud terminates TLS upstream and then sends
   * X-Forwarded-Proto: http on an https request, so that header is unusable.
   */
  private def render(host: String): String =
    val base = s"https://$host"
    Template
      .replace("{{LANGUAGE}}", Language)
      .replace("{{BRANCH}}", Branch)
      .replace("{{BRANCH_URL}}", s"$RepoUrl/tree/$Branch")
      .replace("{{OG_IMAGE}}", s"$base/og.png")
      .replace("{{PAGE_URL}}", s"$base/")
      .replace("{{INDEX_URL}}", IndexUrl)
      .replace("{{EXTRA}}", "")

  private def resource(name: String): Array[Byte] =
    val in = getClass.getResourceAsStream(name)
    require(in != null, s"missing resource $name")
    try in.readAllBytes()
    finally in.close()

  initialize()
