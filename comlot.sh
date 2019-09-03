#!/bin/bash

NOW=$(date +%FT%TZ)
BASEURL="https://blacklist.comlot.ch/"
USERAGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/76.0.3809.132 Safari/537.36"
MIRROR_DIR="/tmp/mirror"
CHECK_DIR="/tmp/check"
GIT_ORIGIN="git@github.com:antoinet/comlot.git"
GIT_USERNAME="comlot bot"
GIT_EMAIL="comlot@schoggi.org"
GIT_STAT_FILE="/tmp/comlot_diff_stat.txt"

function mirror_changes() {
  rm -rf "$MIRROR_DIR"
  mkdir -p "$MIRROR_DIR" && cd "$MIRROR_DIR"
  git init -q .
  git config user.name "$GIT_USERNAME"
  git config user.email "$GIT_EMAIL"
  git remote add origin "$GIT_ORIGIN"
  git pull -q origin master
  rm -rf *
  wget -q --mirror --no-parent --no-directories --user-agent="$USERAGENT" "$BASEURL"
  rm index.html
  if [[ `git status --porcelain` ]]; then
    git diff --stat comlot_blacklist.txt > "GIT_STAT_FILE"
    git add .
    git commit -q -m "automatic commit $NOW"
    git push -q origin master
  fi
}

function check_signatures() {
  mkdir -p "$CHECK_DIR" && cd "$CHECK_DIR"

  # blacklist file
  wget -q --user-agent="$USERAGENT" -O blacklist.txt "$BASEURL/comlot_blacklist.txt"
  # signature
  wget -q --user-agent="$USERAGENT" -O blacklist.txt.sign "$BASEURL/comlot_blacklist.txt.sign"
  # comlot certificate
  wget -q --user-agent="$USERAGENT" -O blacklist.comlot.ch.pub "$BASEURL/blacklist.comlot.ch.pub"
  # intermediate
  wget -q --user-agent="$USERAGENT" -O intermediate.pem "$BASEURL/intermediate.pem"
  # root
  wget -q --user-agent="$USERAGENT" -O ca.pem "$BASEURL/ca.pem"

  # Ensure the file was signed using blacklist.comlot.ch.pub
  openssl base64 -d -in blacklist.txt.sign -out blacklist.txt.der
  openssl dgst -sha256 -verify blacklist.comlot.ch.pub -signature blacklist.txt.der blacklist.txt
  if [ $? -ne 0 ]; then
    return 1
  fi

  # Verify certificate chain
  cat ca.pem intermediate.pem > chain.pem
  openssl verify -CAfile chain.pem blacklist.comlot.ch.pub
  if [ $? -ne 0 ]; then
    return 2
  fi

  # Verify the certificates downloaded from blacklist.comlot.ch are issued by SwissSign
  ## Intermediate SwissSign
  keyid=`openssl x509 -in blacklist.comlot.ch.pub -text -noout | grep -A1 "X509v3 Authority Key Identifier" | tail -1 | sed 's/.*keyid:\(.*\)$/\1/' | sed 's/://g'`
  wget -q -O chain-from-swisssign.der http://swisssign.net/cgi-bin/authority/download/$keyid
  openssl x509 -inform der -in chain-from-swisssign.der -out chain-from-swisssign.crt
  diff intermediate.pem chain-from-swisssign.crt
  if [ $? -ne 0 ]; then
    return 3;
  fi

  ## Root SwissSign
  wget -q -O ca-from-swisssign.der http://swisssign.net/cgi-bin/authority/download/50AFCC078715476F38C5B465D1DE95AAE9DF9CCC
  openssl x509 -inform der -in ca-from-swisssign.der -out ca-from-swisssign.crt
  diff ca.pem ca-from-swisssign.crt
  if [ $? -ne 0 ]; then
    return 4;
  fi

  # Check that the certificate has not been revoked
  url=`openssl x509 -noout -text -in blacklist.comlot.ch.pub | grep -A 4 'X509v3 CRL Distribution Points' | grep URI | awk -FURI: '{ print $2}'`
  wget -q -O revocation.der "$url"
  openssl crl -inform DER -in revocation.der -outform PEM -out revocation.pem
  cat intermediate.pem ca.pem revocation.pem > chain.pem
  openssl verify -crl_check -CAfile chain.pem blacklist.comlot.ch.pub
  if [ $? -ne 0 ]; then
    return 5;
  fi
}


mirror_changes
check_signatures
