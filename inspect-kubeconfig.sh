#!/usr/bin/env bash
# inspect-kubeconfig.sh
# Usage: ./inspect-kubeconfig.sh /path/to/kubeconfig

set -euo pipefail

CFG="${1:-}"
if [[ -z "$CFG" || ! -f "$CFG" ]]; then
  echo "Usage: $0 /path/to/kubeconfig" >&2
  exit 1
fi

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing dependency: $1" >&2
    exit 2
  }
}
need awk
need openssl
need base64
need csplit

# Read entire kubeconfig once
mapfile -t LINES < <(sed -e 's/\r$//' "$CFG")

# Helper: trim
trim() { sed -E 's/^[[:space:]]+|[[:space:]]+$//g'; }

# Helper: get scalar value "key: value" (first occurrence at top level)
get_top_scalar() {
  awk -F: -v key="$1" '
    $0 ~ ("^" key ":") { sub(/^[^:]+:[[:space:]]*/,""); print; exit }
  ' "$CFG" | trim
}

CURRENT_CTX="$(get_top_scalar 'current-context')"
if [[ -z "$CURRENT_CTX" ]]; then
  echo "Could not find current-context in $CFG" >&2
  exit 3
fi

# Parse contexts to find cluster + user for CURRENT_CTX
get_ctx_mapping() {
  awk -v want="$1" '
    BEGIN{in_ctx=0; in_item=0; cluster=""; user=""; name=""}
    /^contexts:/ {in_ctx=1; next}
    in_ctx && /^users:|^clusters:|^preferences:|^current-context:/ {in_ctx=0}
    in_ctx {
      if ($0 ~ /^- +context:/) { in_item=1; cluster=""; user=""; name="" ; next }
      if (in_item && $0 ~ /^[[:space:]]+cluster:/) {
        sub(/^[^:]+:[[:space:]]*/,""); cluster=$0
      }
      if (in_item && $0 ~ /^[[:space:]]+user:/) {
        sub(/^[^:]+:[[:space:]]*/,""); user=$0
      }
      # name is at the same level as "- context:" (less indent)
      if (in_item && $0 ~ /^[[:space:]]{2}name:/) {
        s=$0; sub(/^[^:]+:[[:space:]]*/,"",s); name=s
        if (name==want) { print cluster "\t" user; exit }
        in_item=0
      }
    }
  ' "$CFG"
}

TABMAP="$(get_ctx_mapping "$CURRENT_CTX" || true)"
if [[ -z "$TABMAP" ]]; then
  echo "Could not map context '$CURRENT_CTX' to cluster/user" >&2
  exit 4
fi
CLUSTER_NAME="$(cut -f1 <<<"$TABMAP" | trim)"
USER_NAME="$(cut -f2 <<<"$TABMAP" | trim)"

# Find certificate-authority-data under the chosen cluster
get_cluster_ca_b64() {
  awk -v want="$1" '
    BEGIN{in_clusters=0; in_item=0; gotname=0; name=""; grab=0; buf=""}
    /^clusters:/ {in_clusters=1; next}
    in_clusters && /^users:|^contexts:|^preferences:|^current-context:/ {in_clusters=0}
    in_clusters {
      if ($0 ~ /^- +cluster:/) { in_item=1; gotname=0; name=""; grab=0; buf=""; next }
      if (in_item && $0 ~ /^[[:space:]]{2}name:/) {
        s=$0; sub(/^[^:]+:[[:space:]]*/,"",s); name=s
      }
      if (in_item && $0 ~ /^[[:space:]]+certificate-authority-data:/) {
        # start grabbing b64 on same line + following indented pure b64 lines
        line=$0; sub(/^[^:]+:[[:space:]]*/,"",line); buf=line; grab=1; next
      }
      if (in_item && grab) {
        if ($0 ~ /^[[:space:]]+[A-Za-z0-9+\/=]+[[:space:]]*$/) { s=$0; sub(/^[[:space:]]+/,"",s); buf=buf s; next }
        else { # stop on first non-b64/indent
          if (name==want) { print buf; exit }
          grab=0; buf=""
        }
      }
      # End of item when next item begins
      if (in_item && $0 ~ /^- +cluster:/) {
        if (name==want && buf!="") { print buf; exit }
        gotname=0; name=""; grab=0; buf=""
      }
    }
    END{ if (name==want && buf!="") print buf }
  ' "$CFG" | tr -d '[:space:]'
}

# Find client-certificate-data and client-key-data under the chosen user
get_user_field_b64() {
  local want="$1" key="$2"
  awk -v want="$want" -v key="$key" '
    BEGIN{in_users=0; in_item=0; grab=0; buf=""; name=""}
    /^users:/ {in_users=1; next}
    in_users && /^clusters:|^contexts:|^preferences:|^current-context:/ {in_users=0}
    in_users {
      if ($0 ~ /^- +name:/) { in_item=1; name=$0; sub(/^[^:]+:[[:space:]]*/,"",name); buf=""; grab=0; next }
      if (in_item && $0 ~ /^[[:space:]]+user:/) { next } # enter sub-map
      if (in_item && $0 ~ ("^[[:space:]]+" key ":")) {
        line=$0; sub(/^[^:]+:[[:space:]]*/,"",line); buf=line; grab=1; next
      }
      if (in_item && grab) {
        if ($0 ~ /^[[:space:]]+[A-Za-z0-9+\/=]+[[:space:]]*$/) { s=$0; sub(/^[[:space:]]+/,"",s); buf=buf s; next }
        else {
          if (name==want) { print buf; exit }
          grab=0; buf=""
        }
      }
      if (in_item && $0 ~ /^- +name:/) {
        if (name==want && buf!="") { print buf; exit }
        name=$0; sub(/^[^:]+:[[:space:]]*/,"",name); buf=""; grab=0
      }
    }
    END{ if (name==want && buf!="") print buf }
  ' "$CFG" | tr -d '[:space:]'
}

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

CA_B64="$(get_cluster_ca_b64 "$CLUSTER_NAME" || true)"
USRCRT_B64="$(get_user_field_b64 "$USER_NAME" 'client-certificate-data' || true)"
USRKEY_B64="$(get_user_field_b64 "$USER_NAME" 'client-key-data' || true)"

if [[ -n "$CA_B64" ]]; then
  echo "$CA_B64" | base64 -d > "$TMPDIR/ca_bundle.pem" || {
    echo "Failed to decode certificate-authority-data" >&2
    exit 5
  }
fi
if [[ -n "$USRCRT_B64" ]]; then
  echo "$USRCRT_B64" | base64 -d > "$TMPDIR/user.crt" || true
fi
if [[ -n "$USRKEY_B64" ]]; then
  echo "$USRKEY_B64" | base64 -d > "$TMPDIR/user.key" || true
fi

echo "Current context : $CURRENT_CTX"
echo "Cluster         : $CLUSTER_NAME"
echo "User            : $USER_NAME"
echo

# Print CA bundle certs
echo "=== Cluster CA bundle (certificate-authority-data) ==="
if [[ -s "$TMPDIR/ca_bundle.pem" ]]; then
  # Split bundle into individual certs
  csplit -s -f "$TMPDIR/cert-" "$TMPDIR/ca_bundle.pem" '/-----BEGIN CERTIFICATE-----/' '{*}' || true
  i=0
  for f in "$TMPDIR"/cert-*; do
    [[ -s "$f" ]] || continue
    i=$((i+1))
    echo "--- CA[$i] ---"
    openssl x509 -in "$f" -noout \
      -subject -issuer -serial -startdate -enddate -fingerprint \
      -ext subjectKeyIdentifier -ext authorityKeyIdentifier 2>/dev/null || \
      openssl x509 -in "$f" -noout -text
    echo
  done
else
  echo "(none found)"
fi

# Print user cert
echo "=== User certificate (client-certificate-data) ==="
if [[ -s "$TMPDIR/user.crt" ]]; then
  openssl x509 -in "$TMPDIR/user.crt" -noout \
    -subject -issuer -serial -startdate -enddate -fingerprint \
    -ext subjectKeyIdentifier -ext authorityKeyIdentifier 2>/dev/null || \
    openssl x509 -in "$TMPDIR/user.crt" -noout -text
else
  echo "(none found — this kubeconfig may use a token rather than a client certificate)"
fi
echo

# Key ↔ cert match
echo "=== Client key match check ==="
if [[ -s "$TMPDIR/user.crt" && -s "$TMPDIR/user.key" ]]; then
  if openssl x509 -in "$TMPDIR/user.crt" -noout -modulus 2>/dev/null | openssl md5 >/dev/null && \
     openssl rsa  -in "$TMPDIR/user.key" -noout -modulus 2>/dev/null | openssl md5 >/dev/null && \
     [[ "$(openssl x509 -in "$TMPDIR/user.crt" -noout -modulus 2>/dev/null | openssl md5)" == "$(openssl rsa -in "$TMPDIR/user.key" -noout -modulus 2>/dev/null | openssl md5)" ]]; then
    echo "OK: client-key matches client certificate."
  else
    echo "MISMATCH or encrypted key (cannot compare modulus)."
  fi
else
  echo "(no key and/or cert found)"
fi
echo

# Chain check (often not applicable, but useful)
echo "=== Chain check (user cert vs CA bundle) ==="
if [[ -s "$TMPDIR/user.crt" && -s "$TMPDIR/ca_bundle.pem" ]]; then
  if openssl verify -CAfile "$TMPDIR/ca_bundle.pem" "$TMPDIR/user.crt" >/dev/null 2>&1; then
    echo "Chain OK: user certificate validates against cluster CA bundle."
  else
    echo "Not validated: user cert does not chain to this CA bundle (expected if bundle is server-CA only)."
  fi
else
  echo "(skipped — missing user cert or CA bundle)"
fi
