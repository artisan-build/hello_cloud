package build.artisan.hellocloud

/**
 * The jar's entry point. It exists so the manifest can name a class with a
 * main method declared directly on it, rather than relying on Scala emitting a
 * static forwarder for the one cask.Main contributes to `App`.
 */
object Main:
  def main(args: Array[String]): Unit = App.main(args)
