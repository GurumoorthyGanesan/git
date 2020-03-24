#!/bin/sh

gpg_version=$(gpg --version 2>&1)
if test $? != 127
then
	# As said here: http://www.gnupg.org/documentation/faqs.html#q6.19
	# the gpg version 1.0.6 didn't parse trust packets correctly, so for
	# that version, creation of signed tags using the generated key fails.
	case "$gpg_version" in
	'gpg (GnuPG) 1.0.6'*)
		say "Your version of gpg (1.0.6) is too buggy for testing"
		;;
	*)
		say_color info >&4 "Trying to set up GPG"
		want_trace && set -x
		# Available key info:
		# * Type DSA and Elgamal, size 2048 bits, no expiration date,
		#   name and email: C O Mitter <committer@example.com>
		# * Type RSA, size 2048 bits, no expiration date,
		#   name and email: Eris Discordia <discord@example.net>
		# No password given, to enable non-interactive operation.
		# To generate new key:
		#	gpg --homedir /tmp/gpghome --gen-key
		# To write armored exported key to keyring:
		#	gpg --homedir /tmp/gpghome --export-secret-keys \
		#		--armor 0xDEADBEEF >> lib-gpg/keyring.gpg
		#	gpg --homedir /tmp/gpghome --export \
		#		--armor 0xDEADBEEF >> lib-gpg/keyring.gpg
		# To export ownertrust:
		#	gpg --homedir /tmp/gpghome --export-ownertrust \
		#		> lib-gpg/ownertrust
		mkdir ./gpghome &&
		chmod 0700 ./gpghome &&
		GNUPGHOME="$PWD/gpghome" &&
		export GNUPGHOME &&
		(gpgconf --kill gpg-agent >&3 2>&4 || : ) &&
		gpg --homedir "${GNUPGHOME}" --import \
			"$TEST_DIRECTORY"/lib-gpg/keyring.gpg >&3 2>&4 &&
		gpg --homedir "${GNUPGHOME}" --import-ownertrust \
			"$TEST_DIRECTORY"/lib-gpg/ownertrust >&3 2>&4 &&
		gpg --homedir "${GNUPGHOME}" </dev/null \
			--sign -u committer@example.com >&3 2>&4 &&
		test_set_prereq GPG &&
		# Available key info:
		# * see t/lib-gpg/gpgsm-gen-key.in
		# To generate new certificate:
		#  * no passphrase
		#	gpgsm --homedir /tmp/gpghome/ \
		#		-o /tmp/gpgsm.crt.user \
		#		--generate-key \
		#		--batch t/lib-gpg/gpgsm-gen-key.in
		# To import certificate:
		#	gpgsm --homedir /tmp/gpghome/ \
		#		--import /tmp/gpgsm.crt.user
		# To export into a .p12 we can later import:
		#	gpgsm --homedir /tmp/gpghome/ \
		#		-o t/lib-gpg/gpgsm_cert.p12 \
		#		--export-secret-key-p12 "committer@example.com"
		echo | gpgsm --homedir "${GNUPGHOME}" >&3 2>&4 \
			--passphrase-fd 0 --pinentry-mode loopback \
			--import "$TEST_DIRECTORY"/lib-gpg/gpgsm_cert.p12 &&

		gpgsm --homedir "${GNUPGHOME}" -K 2>&4 |
		grep fingerprint: |
		cut -d" " -f4 |
		tr -d '\n' >"${GNUPGHOME}/trustlist.txt" &&

		echo " S relax" >>"${GNUPGHOME}/trustlist.txt" &&
		echo hello | gpgsm --homedir "${GNUPGHOME}" >&3 2>&4 \
			-u committer@example.com -o /dev/null --sign - &&
		test_set_prereq GPGSM
		;;
	esac
fi

if test_have_prereq GPG &&
    echo | gpg --homedir "${GNUPGHOME}" -b --rfc1991 >&3 2>&4
then
	test_set_prereq RFC1991
fi
want_trace && set +x

sanitize_pgp() {
	perl -ne '
		/^-----END PGP/ and $in_pgp = 0;
		print unless $in_pgp;
		/^-----BEGIN PGP/ and $in_pgp = 1;
	'
}
