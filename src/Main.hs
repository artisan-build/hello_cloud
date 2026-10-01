-- | Hello from Haskell, on Laravel Cloud's Go runtime.
--
-- Laravel Cloud runs this binary because the branch carries a @go.mod@ at its
-- root, so the environment was detected as Go when it was created and Cloud
-- starts whatever executable the build command left at @./app@. The build
-- command for this environment never compiles any Go: it downloads the binary
-- GitHub Actions built from this commit.
--
-- The shared HTML template, the index URL and the OG card are all compiled in
-- with Template Haskell, so nothing on Cloud's ephemeral filesystem matters
-- once the process is up.
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}

module Main (main) where

import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as BL
import Data.FileEmbed (embedFile)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import qualified Data.Text.Lazy as TL
import Network.Wai.Handler.Warp (defaultSettings, setHost, setPort)
import System.Environment (lookupEnv)
import Text.Read (readMaybe)
import Web.Scotty

language, branch, repoUrl :: T.Text
language = "Haskell"
branch = "haskell"
repoUrl = "https://github.com/artisan-build/hello_cloud"

-- | The shared template from @main@. Do not fork it per language.
template :: T.Text
template = TE.decodeUtf8 $(embedFile "shared/page.html")

-- | The index URL, also shared from @main@.
indexUrl :: T.Text
indexUrl = T.strip (TE.decodeUtf8 $(embedFile "shared/index-url.txt"))

-- | Written by @go run ./tools/ogen -language Haskell -out og.png@ before the build.
ogPng :: BS.ByteString
ogPng = $(embedFile "og.png")

main :: IO ()
main = do
    port <- maybe 3000 id . (>>= readMaybe) <$> lookupEnv "PORT"
    -- Cloud's per-instance nginx proxies to 127.0.0.1:$PORT over an IPv6-only
    -- network, so bind the dual-stack wildcard. Warp's "*6" is an AF_INET6
    -- socket with IPV6_V6ONLY left off, which is what that needs.
    let opts =
            defaultOptions
                { verbose = 0
                , settings = setPort port (setHost "*6" defaultSettings)
                }
    putStrLn $ "hello_cloud: hello from " <> T.unpack language <> ", serving on [::]:" <> show port
    scottyOpts opts $ do
        get "/" $ do
            h <- header "Host"
            let host = maybe "localhost" TL.toStrict h
                base = "https://" <> host
            setHeader "Content-Type" "text/html; charset=utf-8"
            raw . BL.fromStrict . TE.encodeUtf8 $ render base
        get "/og.png" $ do
            setHeader "Content-Type" "image/png"
            setHeader "Cache-Control" "public, max-age=3600"
            raw (BL.fromStrict ogPng)

-- | Fills the shared template's seven placeholders.
--
-- @og:image@ and @og:url@ have to be absolute, so they are built from the
-- request's Host header with a hard-coded https scheme: Cloud terminates TLS
-- upstream and then sends @X-Forwarded-Proto: http@ on an https request, so
-- that header cannot be trusted.
render :: T.Text -> T.Text
render base =
    foldl sub template
        [ ("{{LANGUAGE}}", language)
        , ("{{BRANCH}}", branch)
        , ("{{BRANCH_URL}}", repoUrl <> "/tree/" <> branch)
        , ("{{OG_IMAGE}}", base <> "/og.png")
        , ("{{PAGE_URL}}", base <> "/")
        , ("{{INDEX_URL}}", indexUrl)
        , ("{{EXTRA}}", "")
        ]
  where
    sub acc (needle, value) = T.replace needle value acc
