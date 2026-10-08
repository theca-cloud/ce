#!/bin/sh
# Prepares Garage for Theca (compose.s3.yml runs it at every start, before the
# server): the node's layout, the bucket "theca", the S3 key from ./secrets/
# imported and allowed on it, and the bucket's CORS rule for PUBLIC_URL.
# Idempotent: what exists is left as it is; the CORS rule is rewritten, so a
# new PUBLIC_URL applies at the next start.
set -eu

token=$(cat /run/secrets/garage_admin_token)
key=$(cat /run/secrets/s3_access_key)
secret=$(cat /run/secrets/s3_secret_key)
admin() { # endpoint [json]
    curl -fsS -H "Authorization: Bearer $token" -H 'Content-Type: application/json' \
        ${2:+-d "$2"} "http://garage:3903/v2/$1"
}
field() { # name: the first "name":"value" of the JSON on stdin
    tr , '\n' | sed -n "s/.*\"$1\": *\"\([^\"]*\)\".*/\1/p" | head -1
}

attempt=0
until admin GetClusterHealth >/dev/null 2>&1; do
    attempt=$((attempt + 1))
    [ "$attempt" -lt 30 ] || { echo "garage is not answering" >&2; exit 1; }
    sleep 1
done

# The layout: this node holds every partition. The capacity only weighs nodes
# against each other; with one node it limits nothing.
status=$(admin GetClusterStatus)
case "$status" in *'"role": null'* | *'"role":null'*)
    node=$(printf %s "$status" | field id)
    admin UpdateClusterLayout "{\"roles\":[{\"id\":\"$node\",\"zone\":\"dc1\",\"capacity\":1000000000000,\"tags\":[]}]}" >/dev/null
    admin ApplyClusterLayout '{"version":1}' >/dev/null
    echo "layout applied"
    ;;
esac

admin 'GetBucketInfo?globalAlias=theca' >/dev/null 2>&1 ||
    { admin CreateBucket '{"globalAlias":"theca"}' >/dev/null && echo "bucket created"; }
admin "GetKeyInfo?id=$key" >/dev/null 2>&1 ||
    { admin ImportKey "{\"accessKeyId\":\"$key\",\"secretAccessKey\":\"$secret\",\"name\":\"theca\"}" >/dev/null &&
        echo "key imported"; }
bucket=$(admin 'GetBucketInfo?globalAlias=theca' | field id)
admin AllowBucketKey "{\"bucketId\":\"$bucket\",\"accessKeyId\":\"$key\",\"permissions\":{\"read\":true,\"write\":true,\"owner\":true}}" >/dev/null

# Browsers upload and download chunks with presigned URLs, on Garage's origin:
# PUT and GET from the app, the headers those URLs sign, ETag readable
# (docs: decisions.md, the web app's CORS).
curl -fsS --aws-sigv4 "aws:amz:garage:s3" --user "$key:$secret" -X PUT "http://garage:3900/theca?cors" \
    --data-binary "<CORSConfiguration><CORSRule><AllowedOrigin>$PUBLIC_URL</AllowedOrigin><AllowedMethod>PUT</AllowedMethod><AllowedMethod>GET</AllowedMethod><AllowedHeader>x-amz-checksum-sha256</AllowedHeader><AllowedHeader>if-none-match</AllowedHeader><ExposeHeader>ETag</ExposeHeader><MaxAgeSeconds>3600</MaxAgeSeconds></CORSRule></CORSConfiguration>"
echo "Garage ready: bucket theca, CORS for $PUBLIC_URL"
