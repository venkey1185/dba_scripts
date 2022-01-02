#!/bin/bash
#
# NOTES :
# ********
# THIS SCRIPT IS USED TO CREATE/RENEW LETS ENCRYPT CERTIFICATE. ALONG WIHT CERTIFICATE CREATION THIS SCRIPT 
# CREATES WALLET AND PERFORMS ADDITIONAL STEPS TO ENABLE SSL AT OHS LEVEL. THERE ARE FEW DEPENDENCIES BEFORE 
# EXECUTING THIS SCRIPT, PLEASE REVIEW PREREQUISITES SECTION BELOW FOR MORE DETAILS.
# THIS SCRIPT DOWNLOADS DST ROOT CERTIFICATE AND IMPORTS TO ORACLE WALLET.
# ALL PARAMETERS ARE CONFIGURABLE. IF IT IS REQUIRED TO CHANGE EITHER URL OR FMW LOCATIONS, UPDATE THE NECESSARY
# VARIABLES AND RUN THE SCRIPT WITH NEW CERTIFICATE AS INSTALL TYPE.
#
# PREREQUISITES:
# ******************
# 1) The server requires internet access to download dst root certificate
# 2) OHS Server Config files ssl.conf and httpd.conf needs to be updated as per document to use the new wallet files
# 3) OHS Start/Shutdown needs to be configured without password using storeUserConfig parameter
# 4) This scripts supports New & renewal of certificate
# 5) Certbot needs to be preinstalled on Server. Both certbot and OHS should be running same server. 
#    Refer link for instructions - https://certbot.eff.org/instructions
# 6) Application on plain port should be accessible via DOMAIN URL for which SSL needs to be enabled from internet.
#
# USAGE:
# ******************
# sh certbot_update.sh [INSTALL_TYPE] 
#
# Parameter     INSTALL_TYPE
# 0 - To install new certificate
# 1 - To renew existing certificate
#
# Shell         Bourne/Korn
#-------------------------------------------------------------------------------
#   History:
#
#   Date                Name                  Comments
#   ----                ----                  --------
#   Jan. 2022           Venkat Muthadi        Initial Script
#
#-------------------------------------------------------------------------------#

# DEFINE VARIABLES
export PATH=/root/bin:$PATH
SCRIPT_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
TMPL_FILE_LOC=${SCRIPT_DIR}/templates/db
LOGHOME=${SCRIPT_DIR}/logs
EXIT_FILE=$SCRIPT_DIR/logs/${CUSTOMERNAME}_DB_EXIT.log
BACKUP=`date +"%m%d%y%H%M"`
HOSTNAME=`hostname`
WALLET_PASS=Welcome1
OHS_USER=oracle
WEB="kestri.xyz"
CERT_BASE=/etc/letsencrypt/live/${WEB}
ORACLE_HOME=/u01/app/Middleware/Oracle_Home
OHS_COMP=ohs1
ORAWALLET_BASE=$ORACLE_HOME/wallet
DOMAIN_HOME=$ORACLE_HOME/user_projects/domains/base_domain
OHS_INSTANCE=${DOMAIN_HOME}/config/fmwconfig/components/OHS/instances/${OHS_COMP}
OHS_WEBROOT=${OHS_INSTANCE}/htdocs
OHS_WALLET=${OHS_INSTANCE}/keystores/default
ORACLE_COMMON=$ORACLE_HOME/oracle_common
JAVA_HOME=${ORACLE_COMMON}/jdk/jre
export PATH=$ORACLE_COMMON/bin:$JAVA_HOME/bin:$PATH

usage()
{
echo "Usage: sh $0 [INSTALL_TYPE]"
echo 
echo "INSTALL_TYPE PARAMETERS"
echo "0 - To install new certificate"
echo "1 - To renew existing certificate"
echo
exit 2;
}

log_print ()
{
echo "**********************************************************************************"
echo $1
echo "**********************************************************************************"
}

cert_install()
{
log_print "INITIATING CERTIFICATE INSTALL"
echo
echo "Running below command:"
echo "certbot certonly --webroot -d ${WEB} --webroot_path=$OHS_WEBROOT" 
echo
certbot certonly --webroot -d ${WEB} --webroot-path=$OHS_WEBROOT 
if [ $? -eq 0 ];
then
  ls -ltr ${CERT_BASE}/*
  echo
  log_print "CERTIFICATE CREATION IS SUCCESSFUL."
  cd ${CERT_BASE}
  ls -ltr
else
  echo
  log_print "CERTIFICATE CREATION IS FAILED. EXITING.."
  exit 2
fi;

}


cert_renew()
{
log_print "INITIATING CERTIFICATE RENEWAL"
echo
echo "Running below command:"
echo "certbot certonly --webroot --force-renewal -d ${WEB}"
echo
certbot certonly --webroot --force-renewal -d $WEB
if [ $? -eq 0 ];
then
  ls -ltr ${CERT_BASE}/*
  echo
  log_print "CERTIFICATE RENEWAL IS SUCCESSFUL."
else
  echo
  log_print "CERTIFICATE RENEWAL IS FAILED. EXITING.."
  exit 2
fi;
}
wallet_dir_setup()
{

# Verify Base Wallet directory
if [ -d ${ORAWALLET_BASE} ];
then
  echo "Wallet Directory Exists. Performing Backup"
  mkdir -p ${ORAWALLET_BASE}_archive
  cp -pr ${ORAWALLET_BASE} ${ORAWALLET_BASE}_archive/${BACKUP}
  echo "Creating Wallet directory"
  mkdir -p ${ORAWALLET_BASE}  
else
  echo "Wallet Directory is not available. Creating Now.."
  mkdir -p ${ORAWALLET_BASE}_archive ${ORAWALLET_BASE}
  cd ${ORAWALLET_BASE}
  pwd
  ls
fi;

# Copy SSL Certificates
cp -Lpr ${CERT_BASE}/* ${ORAWALLET_BASE}/
cd ${ORAWALLET_BASE}
pwd
ls -ltr
}

keystore_setup()
{

# Generate wallet certificates from SSL
log_print "CREATING PKCS WALLET FROM PEM FILES"
echo
cd ${ORAWALLET_BASE}
openssl pkcs12 -export -inkey privkey.pem -in cert.pem -out oracle_wallet.pkcs12 -certfile chain.pem -password pass:${WALLET_PASS}
echo

echo "Download DST Root Cert File"
curl  https://crt.sh/?d=8395 > ${ORAWALLET_BASE}/dst_root.pem
# log_print "CONVERTING PKCS WALLET TO KEYSTORE"
echo
cd ${ORAWALLET_BASE}
# { echo ${WALLET_PASS}; echo ${WALLET_PASS}; echo ${WALLET_PASS}; } | keytool -v -importkeystore -srckeystore oracle_wallet.pkcs12 -srcstoretype PKCS12 -destkeystore oracle_wallet.jks  -deststoretype JKS
ls -ltr ${ORAWALLET_BASE}/
echo
echo "Importing Trust certificate"
#{ echo ${WALLET_PASS}; } | keytool -import -alias Root -keystore oracle_wallet.jks -trustcacerts -file chain.pem -noprompt
sleep 2
#{ echo ${WALLET_PASS}; } | keytool -import -alias RootCA -keystore oracle_wallet.jks -trustcacerts -file fullchain.pem -noprompt
sleep 2
chown -R oracle:oinstall ${ORAWALLET_BASE}

echo
}


ora_wallet_setup()
{
log_print "CREATE ORACLE WALLET FROM KEYSTORE"
su - oracle <<EOF
echo "ORACLE HOME --> $ORACLE_HOME"
echo "ORACLE COMMON --> $ORACLE_COMMON"
echo "JAVA HOME --> $JAVA_HOME"
echo "WALLET LOC -->$ORAWALLET_BASE"
echo "OHS WALLET LOC -->$OHS_WALLET"
export PATH=$ORACLE_COMMON/bin:$JAVA_HOME/bin:$PATH

echo "Switch to oracle user is successful."
echo

cd ${ORAWALLET_BASE}

echo "Rename Wallet and enable autologin"
cp -pr oracle_wallet.pkcs12 ewallet.p12
echo "Adding DST Root Certificate to Wallet"
orapki wallet add -wallet . -trusted_cert -cert dst_root.pem -pwd ${WALLET_PASS}
echo "Verify wallet content"
orapki wallet display -wallet . -pwd ${WALLET_PASS}
orapki wallet create -wallet ./ -pwd ${WALLET_PASS} -auto_login


# echo "Convert jks file to Oracle Wallet mode"
#orapki wallet jks_to_pkcs12 -wallet ./ -pwd ${WALLET_PASS} -keystore oracle_wallet.jks -jkspwd ${WALLET_PASS}
echo
sleep 2
ls -ltr
EOF

}

ohs_setup()
{
log_print "REPLACE WALLET FROM OHS KEYSTORE"
su - ${OHS_USER} <<EOF
echo
echo "Performing backup of exisitng keystore file"
cd $OHS_WALLET
mkdir BACKUP_$BACKUP
cp -pr *.* BACKUP_$BACKUP

echo "Copy of new wallets in progress.."
cp -pr ${ORAWALLET_BASE}/cwallet* $OHS_WALLET/
cp -pr ${ORAWALLET_BASE}/ewallet* $OHS_WALLET/
ls -ltr
pwd
sleep 2
echo 
EOF
}

ohs_restart()
{
log_print "BOUNCE OF OHS INITIATED.."
su - ${OHS_USER} <<EOF
echo "Shut down of ohs is in progress"
cd ${DOMAIN_HOME}/bin
./stopComponent.sh ohs1
sleep 4
echo
echo "**********************************************************************************"
echo "STARTUP OHS IN PROGRESS"
echo "**********************************************************************************"
cd ${DOMAIN_HOME}/bin
./startComponent.sh ohs1
echo 
sleep 4
curl https://${WEB}
if [ $? -eq 0 ];
then
  echo "BOUNCE IS SUCCESSFUL."
  echo
  echo "CERTIFICATE RENEWAL FOR APPLICATION IS SUCCESSFUL"
else
  echo "BOUNCE IS FAILED."
  echo
  echo "Please review the logfile for more details."
  echo
  echo "Logfile for Session --> ${LOGHOME}/certbot_renew_${BACKUP}.log"
  exit 1
fi;

EOF

}

# Actual Execution starts here

if [ $# -ne 1 ];
then
  echo "Error: Invalid input Parameters!!"

  usage 
fi;


if [ $1 -eq 0 ];
then
  echo "Install of Certificates"
  cert_install | tee -a ${LOGHOME}/certbot_renew_${BACKUP}.log 2>&1
  sleep 2
elif [ $1 -eq 1 ];
then
  echo "Renewal of Certificates"
  cert_renew | tee -a ${LOGHOME}/certbot_renew_${BACKUP}.log 2>&1
  sleep 2
else
  echo "Invalid Input parameter --> $1"
  echo "0 or 1 are the only valid inputs."
  echo
  usage
fi;

mkdir -p ${LOGHOME}

echo "Checking Directory information"
wallet_dir_setup | tee -a ${LOGHOME}/certbot_renew_${BACKUP}.log 2>&1

echo "Keystore setup for letsencrypt certificates"
keystore_setup | tee -a ${LOGHOME}/certbot_renew_${BACKUP}.log 2>&1
sleep 2
echo "Oracle wallet setup in progress"
ora_wallet_setup | tee -a ${LOGHOME}/certbot_renew_${BACKUP}.log 2>&1
sleep 2
echo "update to ohs wallet in progress"
ohs_setup | tee -a ${LOGHOME}/certbot_renew_${BACKUP}.log 2>&1
sleep 2
echo "Restarting OHS Services" 
ohs_restart | tee -a ${LOGHOME}/certbot_renew_${BACKUP}.log 2>&1

echo
echo "Logfile for Session --> ${LOGHOME}/certbot_renew_${BACKUP}.log"