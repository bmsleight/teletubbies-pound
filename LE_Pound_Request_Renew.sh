#!/bin/bash
# -----------------------------------------------------------------
# v1.0
# This script will use Lets Encrypt (LE) to request and/or renew certificates automatically.
# The script will also concatenate the private key and cert chain (Pound's format) and make it available to Pound Load Balancer
# -----------------------------------------------------------------

# Parameters
# -----------------------------------------------------------------
# domains to request certs for, separated by a space
domains=(determine.org.uk www.determine.org.uk myth.barwap.com www.barwap.com barwap.com)
# email address to user when registering certs
email=bms.LE@barwap.com
# LE Binary folder (LE binaries)
le_bin=/etc/letsencrypt
# LE Output Folder (default /etc/letsencrypt)
le_output=/etc/letsencrypt
# Port to bind LE standalone server to
le_port=8000
# Pound folder
pound_fol=/etc/pound
# Pound Cert folder
pound_cfol=${pound_fol}/certs
# -----------------------------------------------------------------
# ------ Do not edit beyond this point ----------------------------

# Functions
# -----------------------------------------------------------------
# function extracts the number of days the cert in question is still valid for
# Original work by Acetylator (https://community.letsencrypt.org/t/how-to-completely-automating-certificate-renewals-on-debian/5615)
get_days_exp() {
	echo "grep the number of days the cert if valid for"
	local d1=$(date -d "`openssl x509 -in $1 -text -noout|grep "Not After"|cut -c 25-`" +%s)
	local d2=$(date -d "now" +%s)

	echo "Return result in global variable"
	days_exp=$(echo \( $d1 - $d2 \) / 86400 |bc)
}

# Function to create certificate is pound's required format
create_pound_cert() {
	echo "Create a PEM file in Pound's format / Combine the private key with fullchain"
	cat ${1} > ${3}
	cat ${2} >> ${3}

    echo "Fix owner and permissions for ${3}"
	chown www-data:www-data ${3}
	chmod 644 ${3}
}
#-----------------------------------------------------------------

# Execution
# -----------------------------------------------------------------
# Create Pound certs folder if it does not exists yet
# Make sure that the cert paths point to the correct folder in the Pound config file
restart=0
if [ ! -d ${pound_cfol} ]; then
	echo "creating ${pound_cfol}"
	mkdir ${pound_cfol}

	echo "fix owner and permissions for ${pound_cfol}"
	chown www-data:www-data ${pound_cfol}
fi

echo "For each domain in '$domains' array check certs"
for domain_name in "${domains[@]}"
	do
		# Variables for this for loop (Required as it used the domain_name from the domains array)
		# ---------------------------
		# LE Live folder
		le_live=${le_output}/live/${domain_name}
		# LE live certs
		le_cert=${le_live}/cert.pem
		# Pound cert folder for every domain
		pound_cert=${pound_cfol}/${domain_name}
		# ---------------------------

		# if a Pound cert file does not exist
		echo "Checking if ${pound_cert} exists"
		if [ ! -e ${pound_cert}  ]; then
			echo "${pound_cert} does not exist"

			# if a LE cert does not exist request it
			echo "Checking if ${le_cert} exists"
			if [ ! -e ${le_cert} ]; then
				echo "${le_cert} does not exist"
				echo "Requesting cert for ${domain_name}"
				${le_bin}/letsencrypt-auto certonly --standalone --agree-tos --domains ${domain_name} --email ${email} --standalone-supported-challenges http-01 --http-01-port 8000 --renew-by-default
			fi

			echo "Creating pound cert for ${domain_name}"
			create_pound_cert ${le_live}/privkey.pem ${le_live}/fullchain.pem ${pound_cert}

			echo "set parameter used to determine if pound needs to be restarted"
			restart=1
		fi

		echo "Check the number of days the cert is still valid for"
		get_days_exp "${le_cert}"
		echo "${domain_name}'s cert is valid for another ${days_exp}"

		# If the certificate is valid for 30 or less days
		if [ ${days_exp} -le "30" ]; then
			# The renew command is the same as the initial request command - it will use the config file in ${le_output}/renewal
			# if you used LE for this domain before (for example using the test parameter) you may need to alter the renew config file
			echo "Renewing cert for ${domain_name}"
			${le_bin}/letsencrypt-auto certonly --standalone --agree-tos --domains ${domain_name} --email ${email} --standalone-supported-challenges http-01 --http-01-port 8000 --renew-by-default

			echo "Creating pound cert for ${domain_name}"
			create_pound_cert ${le_live}/privkey.pem ${le_live}/fullchain.pem ${pound_cert}

            echo "set parameter used to determine if pound needs to be restarted"
			restart=1
		fi
	done

if [ ${restart} -eq "1" ]; then
	echo "Restart Pound to load new certs"
	/etc/init.d/pound restart
else
	echo "No new or renewed certs - no restart required"
fi
# -----------------------------------------------------------------
