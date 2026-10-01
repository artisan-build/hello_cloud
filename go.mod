// A go.mod at the repository root is the whole trick: Laravel Cloud detects the
// Go runtime from it when an environment is created, and then starts whatever
// executable the build left at ./app. On `main` the module is real -- the index
// server and the OG card generator are genuinely Go. On a language branch the
// build command never runs `go build` at all; this file is there to be seen.
module github.com/artisan-build/hello_cloud

go 1.24.0

require golang.org/x/image v0.35.0

require golang.org/x/text v0.34.0 // indirect
