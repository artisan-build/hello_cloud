-- Every byte of the page body is produced here. The C host embeds this file,
-- hands it the shared template, the shared index URL and the branch facts as
-- globals, and then calls render(host) once per request.

local PLACEHOLDERS = "{{([%u_]+)}}"

-- The shared index URL blob has a trailing newline.
local INDEX = INDEX_URL:gsub("%s+$", "")

function render(host)
  local base = "https://" .. host
  local values = {
    LANGUAGE = LANGUAGE,
    BRANCH = BRANCH,
    BRANCH_URL = REPO_URL .. "/tree/" .. BRANCH,
    -- og:image and og:url must be absolute. The scheme is hard-coded: Cloud
    -- terminates TLS upstream and then sends X-Forwarded-Proto: http on an
    -- https request, so that header cannot be used.
    OG_IMAGE = base .. "/og.png",
    PAGE_URL = base .. "/",
    INDEX_URL = INDEX,
    EXTRA = "",
  }

  -- A replacement function, not a replacement string: gsub treats % in a
  -- string replacement as an escape, and these URLs may contain one.
  local body = (TEMPLATE:gsub(PLACEHOLDERS, function(key)
    return values[key] or ""
  end))
  return body
end
