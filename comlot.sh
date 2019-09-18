#!/bin/bash

NOW=$(date +%FT%TZ)
BASEURL="https://blacklist.comlot.ch/"
USERAGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/76.0.3809.132 Safari/537.36"
SHA1_FILE="/root/comlot.sha1"
EMAIL_TEMPL="/root/comlot.msg"
EMAIL_RCPT="antoine@schoggi.org"
MIRROR_DIR="/tmp/mirror"
GIT_ORIGIN="git@github.com:antoinet/comlot.git"
GIT_USERNAME="comlot bot"
GIT_EMAIL="comlot@schoggi.org"
GIT_STAT_FILE="/tmp/comlot_diff_stat.txt"
TWITTER_CREDS="/root/.twitter-keys"

function check_changes() {
  # checks whether contents of blacklist.comlot.ch has changed
  echo "[*] check changes on blacklist.comlot.ch" 
  s1=`/usr/bin/curl -s https://blacklist.comlot.ch | /usr/bin/sha1sum | /usr/bin/cut -f1 -d" "`
  s2=`cat $SHA1_FILE`
  if [ "$s1" != "$s2" ]; then
  	echo "$s1" > "$SHA1_FILE"
  	/usr/sbin/ssmtp "$EMAIL_RCPT" < "$EMAIL_TEMPL"
  else
	echo "  no changes"
	return 1
  fi
}

function clone_repository() {
  echo "[*] clone repository"
  rm -rf "$MIRROR_DIR"
  mkdir -p "$MIRROR_DIR" && cd "$MIRROR_DIR"
  git init -q .
  git config user.name "$GIT_USERNAME"
  git config user.email "$GIT_EMAIL"
  git remote add origin "$GIT_ORIGIN"
  git pull -q origin master
}

function download_changes() {
  echo "[*] download changes"
  cd "$MIRROR_DIR"
  rm -rf *
  wget -q --mirror --no-parent --no-directories --user-agent="$USERAGENT" "$BASEURL"
  rm index.html
}

function push_changes() {
  echo "[*] push changes"
  if [[ `git status --porcelain` ]]; then
    git diff --stat comlot_blacklist.txt > "$GIT_STAT_FILE"
    git add .
    git commit -q -m "automatic commit $NOW"
    git push -q origin master
  else
    echo "  no changes pushed"
  fi
}

function check_blacklist_signature() {
  echo "[*] check blacklist signature"
  cd "$MIRROR_DIR"
  openssl base64 -d -in comlot_blacklist.txt.sign -out comlot_blacklist.txt.sign.der
  openssl dgst -sha256 -verify blacklist.comlot.ch.pub -signature comlot_blacklist.txt.sign.der comlot_blacklist.txt
  if [ $? -ne 0 ]; then
    echo "blacklist signature verification failed" >&2
    return 1
  fi
}

function check_pubkey_signature() {
  echo "[*] check pubkey signature"
  cd "$MIRROR_DIR"
  cat ca.pem intermediate.pem > chain.pem
  openssl verify -CAfile chain.pem blacklist.comlot.ch.pub
  if [ $? -ne 0 ]; then
    echo "certificate chain verification failed" >&2
    return 1
  fi
}

function check_intermediate_signature() {
  echo "[*] check intermediate signature"j
  cd "$MIRROR_DIR"
  keyid=`openssl x509 -in blacklist.comlot.ch.pub -text -noout | grep -A1 "X509v3 Authority Key Identifier" | tail -1 | sed 's/.*keyid:\(.*\)$/\1/' | sed 's/://g'`
  wget -q -O chain-from-swisssign.der http://swisssign.net/cgi-bin/authority/download/$keyid
  openssl x509 -inform der -in chain-from-swisssign.der -out chain-from-swisssign.crt
  diff intermediate.pem chain-from-swisssign.crt
  if [ $? -ne 0 ]; then
    echo "intermediate certificate validation failed" >&2
    return 1;
  fi
}

function check_root_signature() {
  echo "[*] check root signature"
  cd "$MIRROR_DIR"
  ## Root SwissSign
  wget -q -O ca-from-swisssign.der http://swisssign.net/cgi-bin/authority/download/50AFCC078715476F38C5B465D1DE95AAE9DF9CCC
  openssl x509 -inform der -in ca-from-swisssign.der -out ca-from-swisssign.crt
  diff ca.pem ca-from-swisssign.crt
  if [ $? -ne 0 ]; then
    echo "root certificate mismatch" >&2
    return 1;
  fi
}

function check_certificate_revocation() {
  echo "[*] check certificate revocations"
  # Check that the certificate has not been revoked
  url=`openssl x509 -noout -text -in blacklist.comlot.ch.pub | grep -A 4 'X509v3 CRL Distribution Points' | grep URI | awk -FURI: '{ print $2}'`
  wget -q -O revocation.der "$url"
  openssl crl -inform DER -in revocation.der -outform PEM -out revocation.pem
  cat intermediate.pem ca.pem revocation.pem > chain.pem
  openssl verify -crl_check -CAfile chain.pem blacklist.comlot.ch.pub
  if [ $? -ne 0 ]; then
    echo "certificate validation failed, revoked" >&2
    return 1;
  fi
}


check_changes && \
clone_repository && \
download_changes && \
push_changes && \
check_blacklist_signature && \
check_pubkey_signature && \
check_intermediate_signature && \
check_root_signature && \
check_certificate_revocation

if [ $? -ne 0 ]; then
  echo "invalid signature" >&2
  SIG_LINE='signature: \xe2\x9d\x8c'
else
  SIG_LINE='signature: \xe2\x9c\x85'
fi

# create tweet
#
MESSAGE="\xf0\x9f\x9a\xa8 blacklist alert \xf0\x9f\x9a\xa8\n\n"
MESSAGE="$MESSAGE"`awk 'NR==1' $GIT_STAT_FILE`"\n"
MESSAGE="$MESSAGE"`awk 'NR==2' $GIT_STAT_FILE`"\n"
MESSAGE="${MESSAGE}\n${SIG_LINE}\n"
MESSAGE="${MESSAGE}\nhttps://github.com/antoinet/comlot/commits/"

t update "`echo -e $MESSAGE`"
echo -e "$MESSAGE"

