#!/usr/bin/env sh
# The README's screenshots (screenshots/*.png), retaken at releases: the smoke
# test's instance (the image just built), filled with demo data through the API
# and WebDAV, each page shot by Playwright's CLI with the admin's session.
#   scripts/screenshots.sh                     every page from that instance
#   scripts/screenshots.sh URL EMAIL PASSWORD  the user's pages (browse, a file,
#       search, trash, login) from a live instance instead, e.g. the demo just
#       after its reset; the organization's and the admin's pages stay local
#       (the admin pages need an admin; SEARCH and PICTURE fit the queries
#       to its content, e.g. SEARCH=jpg PICTURE=.jpg for the demo)
# Needs what scripts/smoke.sh needs, and npx (Playwright: web's version, its
# Chromium installed once with npx playwright@<version> install chromium).
set -eu
cd "$(dirname "$0")/.."
export npm_config_loglevel=error

playwright=1.63.0 # web's @playwright/test
url=http://localhost:8099
dir=.smoke
out=screenshots
search=${SEARCH:-2026} # the search page's query
picture=${PICTURE:-.png} # live: the file page's picture, the first name matching it
jar=$dir/cookies

scripts/smoke.sh --keep
trap 'docker compose -p theca-smoke down -v >/dev/null 2>&1; rm -rf "$dir"' EXIT

api() { # method path [json]
    curl -fsS -X "$1" -b "$jar" -H 'Content-Type: application/json' ${3:+-d "$3"} "$url/api/v1$2"
}
app=$(api POST /auth/app-passwords '{"name": "demo"}' | jq -r .password)
dav() { # method path [curl options]: path below /dav/, spaces allowed
    method=$1 path=$(printf %s "$2" | sed 's/ /%20/g')
    shift 2
    curl -fsS -o /dev/null -u "demo:$app" -X "$method" "$@" "$url/dav/$path"
}
day=0
put() { # path file: each file a day older than the previous (X-OC-Mtime, as
    # a client gives its files' times), from 1 October 2026 back
    day=$((day + 1))
    dav PUT "$1" -T "$2" -H "X-OC-Mtime: $((1790845200 - day * 86400 - day * 3917))"
}
bytes() { # size: a file of that many random bytes
    head -c "$1" /dev/urandom >"$dir/bytes"
    echo "$dir/bytes"
}
photo() { # sky ground name: a landscape, rendered by Playwright
    html="<body style='margin:0'><svg width='1600' height='800' viewBox='0 267 1600 800' xmlns='http://www.w3.org/2000/svg'><defs><linearGradient id='s' x1='0' y1='0' x2='0' y2='1'><stop offset='0' stop-color='$1'/><stop offset='1' stop-color='#fbe3c4'/></linearGradient></defs><rect width='1600' height='1067' fill='url(#s)'/><circle cx='1150' cy='380' r='90' fill='#fff4e0'/><path d='M0 700 L300 420 L520 620 L800 330 L1100 640 L1350 470 L1600 650 V1067 H0Z' fill='#5b7c99'/><path d='M0 820 L260 640 L560 800 L900 600 L1250 820 L1600 700 V1067 H0Z' fill='#3d5a73'/><rect y='900' width='1600' height='167' fill='$2'/></svg></body>"
    npx -y "playwright@$playwright" screenshot --viewport-size 1600,800 \
        "data:text/html,$(printf %s "$html" | sed 's/#/%23/g')" "$dir/$3.png" >/dev/null
}

echo "Demo data..."
# The smoke test's organization and library, renamed; its test file gone.
org=$(api GET /me | jq -r '.organizations[] | select(.name == "Smoke") | .organization')
api PATCH "/organizations/$org" '{"name": "Acme"}' >/dev/null
docs=$(api GET /libraries | jq -r '.[] | select(.name == "Files") | .id')
api PATCH "/libraries/$docs" '{"name": "Documents"}' >/dev/null
root=$(api GET /libraries | jq -r --arg l "$docs" '.[] | select(.id == $l) | .root')
test_file=$(api GET "/nodes/$root/children" | jq -r '.[] | select(.name == "file") | .id')
# To the trash, then out of it (a purge only takes what's in the trash).
for permanent in false true; do
    api POST /nodes/trash "$(jq -n --arg n "$test_file" --argjson p $permanent '{nodes: [$n], permanent: $p}')" |
        jq -e 'all(.error == null)' >/dev/null || { echo "purging the smoke test's file failed" >&2; exit 1; }
done
photos=$(api POST /libraries "$(jq -n --arg o "$org" '{organization: $o, name: "Photos"}')" | jq -r .id)
api POST /libraries "$(jq -n --arg o "$org" '{organization: $o, name: "Projects"}')" >/dev/null

for folder in Contracts Invoices "Meeting notes"; do dav MKCOL "Acme/Documents/$folder"; done
put "Acme/Documents/Contracts/Office lease 2026.pdf" "$(bytes 482133)"
put "Acme/Documents/Contracts/Hosting agreement.pdf" "$(bytes 210554)"
for month in 07 08 09; do put "Acme/Documents/Invoices/2026-$month Hosting.pdf" "$(bytes 88${month}1)"; done
cat >"$dir/notes.md" <<'EOF'
# Weekly meeting, 6 October 2026

- Website redesign: wireframes approved, development starts next week.
- Budget 2027: first draft shared, comments by Friday.
- New office: the lease is signed, moving on 1 November.
EOF
put "Acme/Documents/Meeting notes/2026-10-06.md" "$dir/notes.md"
# A file with history: three versions.
for size in 31200 33870 35112; do put "Acme/Documents/Budget 2027.xlsx" "$(bytes $size)"; done
put "Acme/Documents/Company handbook.pdf" "$(bytes 2481120)"
put "Acme/Documents/Logo.svg" "$(bytes 14210)"
# In the trash.
put "Acme/Documents/Old budget draft.xlsx" "$(bytes 29011)"
put "Acme/Documents/Scan 0012.pdf" "$(bytes 912000)"
dav DELETE "Acme/Documents/Old budget draft.xlsx"
dav DELETE "Acme/Documents/Scan 0012.pdf"

dav MKCOL "Acme/Photos/Team offsite 2026"
photo '#f6b26b' '#2f6f6f' lake
photo '#9fc5e8' '#38761d' meadow
photo '#c27ba0' '#1c4587' dusk
put "Acme/Photos/Team offsite 2026/Lake.png" "$dir/meadow.png"
put "Acme/Photos/Team offsite 2026/Lake.png" "$dir/lake.png" # a second version
put "Acme/Photos/Team offsite 2026/Meadow.png" "$dir/meadow.png"
put "Acme/Photos/Team offsite 2026/Dusk.png" "$dir/dusk.png"
for folder in "Website redesign" "Mobile app"; do dav MKCOL "Acme/Projects/$folder"; done
put "Acme/Projects/Website redesign/Brief.md" "$dir/notes.md"

child() { # node name: the child's ID
    api GET "/nodes/$1/children" | jq -r --arg n "$2" '.[] | select(.name == $n) | .id'
}
offsite=$(child "$(api GET /libraries | jq -r --arg l "$photos" '.[] | select(.id == $l) | .root')" "Team offsite 2026")
lake=$(child "$offsite" Lake.png)

state() { # the session for the browser (localhost counts as secure: the Secure cookie goes)
    session=$(awk '$6 == "theca_session" {print $7}' "$jar")
    host=${url#*://}
    jq -n --arg v "$session" --arg d "${host%%[:/]*}" '{cookies: [{name: "theca_session", value: $v, domain: $d,
        path: "/", expires: -1, httpOnly: true, secure: true, sameSite: "Lax"}], origins: []}' >"$dir/state.json"
}
state
shot() { # name path height [playwright options]
    name=$1 path=$2 height=$3
    shift 3
    npx -y "playwright@$playwright" screenshot --viewport-size "1440,$height" --color-scheme light \
        --wait-for-timeout 1500 "$@" "$url$path" "$out/$name.png" >/dev/null
    echo "  $out/$name.png"
}

echo "Screenshots..."
mkdir -p "$out"
shot organization "/$org/settings" 900 --load-storage "$dir/state.json"
shot admin "/admin/settings" 900 --load-storage "$dir/state.json"
if [ $# -ge 3 ]; then
    url=${1%/} jar=$dir/remote
    curl -fsS -c "$jar" -H 'Content-Type: application/json' -o /dev/null \
        -d "$(jq -n --arg e "$2" --arg p "$3" '{email: $e, password: $p}')" "$url/api/v1/auth/login"
    state
    # Its first company organization and library, and a picture in it.
    org=$(api GET /me | jq -r '[.organizations[] | select(.personal | not)][0].organization')
    docs=$(api GET /libraries | jq -r --arg o "$org" '[.[] | select(.organization == $o)] | sort_by(.name)[0].id')
    picture=$(api GET "/search?q=$picture&organization=$org" | jq -c '.[0]')
    photos=$(printf %s "$picture" | jq -r .library) lake=$(printf %s "$picture" | jq -r .id)
fi
shot browse "/$org/$docs" 900 --load-storage "$dir/state.json"
shot file "/$org/$photos/$lake" 900 --load-storage "$dir/state.json"
shot search "/search?q=$search" 900 --load-storage "$dir/state.json"
shot trash "/trash?library=$docs" 900 --load-storage "$dir/state.json"
shot login "/login" 900
