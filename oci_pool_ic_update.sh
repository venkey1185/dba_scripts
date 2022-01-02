#!/bin/bash
#####################################################################################################
# SCRIPT NAME   : oci_pool_ic_update.sh.sh                                                          #
# DESCRIPTION   : Initial base version to update Instance Pool with new instance config             #
# USAGE         : sh oci_pool_ic_update.sh <customer name>                                          #
# INITIAL DATE  : 31-Oct-2021                                                                       #
# ASSUUMPTIONS  : 1. This can be executed only on server where OCICLI is installed.                 #
#                 2. It requires oci user auth setup done already and config file is in place       #
#                 3. This works only for existing customer servers, properties needs to available   #
#####################################################################################################
# Mod Date  Rev   Initials  Action     Modification Notes                                           #
# --------  ----  --------- ---------  -------------------------------------------                  #
# 31/10/21  1.0   VM                  Initial Creation - from base version                          #
#####################################################################################################


##############################
#   FUNCTION PLACE HOLDER    #
##############################
get_ocid()
{
echo "Extracting ${NWCOMPMNT} Compartment OCID"
# Network Compartment ID
nwcompid=`oci iam compartment list  --query "data [?\"name\"=='${NWCOMPMNT}'].{OCID:\"id\"}" | grep OCID | awk -F'[\"|\"]' '{print $4}'`
echo ${nwcompid}

# WATS Compartment ID
echo "Extracting ${VMCOMPMNT} Compartment OCID"
watscompid=`oci iam compartment list  --query "data [?\"name\"=='${VMCOMPMNT}'].{OCID:\"id\"}" | grep OCID | awk -F'[\"|\"]' '{print $4}'`
echo ${watscompid}


# Private Network VCN ID
echo "Extracting ${APXVCNNAME} VCN OCID"
privcnOCID=`oci network vcn list  --compartment-id ${nwcompid} --query "data [?\"display-name\"=='${APXVCNNAME}'].{OCID:\"id\"}" | grep OCID | awk -F'[\"|\"]' '{print $4}'`
echo ${privcnOCID}

# Private Network VCN Subnet ID
echo "Extracting ${APXSNNAME} Private Subnet OCID"
privsnid=`oci network subnet list --vcn-id ${privcnOCID} --compartment-id ${nwcompid} --query "data [?\"display-name\"=='${APXSNNAME}'].{OCID:\"id\"}" | grep OCID | awk -F'[\"|\"]' '{print $4}'`
echo ${privsnid}

# Pubic Network VCN Subnet ID
echo "Extracting ${LBSNNAME} Public Subnet OCID"
pubsnid=`oci network subnet list --vcn-id ${pubvcnOCID} --compartment-id ${nwcompid} --query "data [?\"display-name\"=='${LBSNNAME}'].{OCID:\"id\"}" | grep OCID | awk -F'[\"|\"]' '{print $4}'`
echo ${pubsnid}


# UBUNTU VM Image OCID
echo "Extracting ${UBIMG} Image OCID"
UBimageOCID=`oci compute image list --compartment-id ${watscompid}  --query "data [?\"display-name\"=='${UBIMG}'].{OCID:\"id\"}" --all | grep OCID | awk -F'[\"|\"]' '{print $4}'`
echo ${UBimageOCID}



# APX VM INSTANCE OCID
#echo "Extracting ${UBIMG} Image OCID"
#APXVMOCID=`oci compute instance list --query "data [?\"display-name\"=='${APXVMNAME}'].{OCID:\"id\"}" | grep OCID | awk -F'[\"|\"]' '{print $4}'`

# GET INSTANCE CONFIG OCID
echo "Getting OCID of Instance Configuration $IC_NAME"
ICOCID=`oci compute-management instance-configuration list --compartment-id ${watscompid} --query "data [?\"display-name\"=='${IC_NAME}'].{OCID:\"id\"}" | grep OCID | awk -F'[\"|\"]' '{print $4}'`

# GET INSTANCE POOL OCID
echo "Getting OCID of Instance Pool $IP_NAME"
IPOOLOCID=`oci compute-management instance-pool list --compartment-id ${watscompid} --query "data [?\"display-name\"=='${IP_NAME}'].{OCID:\"id\"}" | grep OCID | awk -F'[\"|\"]' '{print $4}'`


}



# DEFINE VARIABLES
export PATH=/root/bin:$PATH
export PATH=/home/oci/.local/bin:/u01/oci_base/oci/bin:$PATH
CUSTOMERNAME=$1
SCRIPT_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
LOGDIR=${SCRIPT_DIR}/logs
. ${SCRIPT_DIR}/conf/wats_${CUSTOMERNAME}.properties
EXIT_FILE=$SCRIPT_DIR/logs/${CUSTOMERNAME}_EXIT.log
TAGNAME="{\"SystemInfo\": {\"customer-name\": \"$CUSTOMERNAME\"}}"

IC_JSON_FILE=${SCRIPT_DIR}/templates/as_tmpl/ic_create_${CUSTOMERNAME}.json
CLOUDINITFILE=${SCRIPT_DIR}/templates/as_tmpl/cloudinit_${CUSTOMERNAME}_b64
IP_JSON_FILE=${SCRIPT_DIR}/templates/as_tmpl/ip_create_${CUSTOMERNAME}.json
AS_JSON_FILE=${SCRIPT_DIR}/templates/as_tmpl/as_create_${CUSTOMERNAME}.json
SSH_KEY=`cat ${VMPUBKEYFILE}`

echo "Profile is $OCI_CLI_PROFILE"

if [ -s ${EXIT_FILE} ] ;then
  echo "exit file exists"
  exit_code=`cat $EXIT_FILE 2>&1`
  #echo "error one "$exit_code
else
  echo "there is no exit file.. creating new one"
  echo "ZERO" > ${EXIT_FILE}
  exit_code="ZERO"
fi

echo "the exit_code is "$exit_code

# VERIFY OCI CONNECTION
oci os ns get


echo "GETTING OCID FOR OCI COMPONENTS"
echo
get_ocid
echo

echo "Rename existing instance configuration"
echo "oci compute-management instance-configuration update --instance-configuration-id ${ICOCID} --display-name ${IC_NAME}_old  --wait-for-state RUNNING"
oci compute-management instance-configuration update --instance-configuration-id ${ICOCID} --display-name ${IC_NAME}_old --force
sleep 3
OLDNAME=`oci compute-management instance-configuration get --instance-configuration-id ${ICOCID} | grep ${IC_NAME}_old  | wc -l`
if [ ${OLDNAME} -ne 1 ];
then
  echo "Renaming existing instance pool failed. Exiting.."
  exit 1;
fi;



# Create Instance Configuration for Ubuntu
if [ "$exit_code" = "ZERO" ];
then
  echo "CREATE UBUNTU INSTANCE CONFIGURATION IN COMPARTMENT ${VMCOMPMNT}"
  echo

  sleep 10
  echo "Proceeding with creation of Instance Configuration"
  cp -pr ${ICJSON} ${IC_JSON_FILE}
  echo "Converting Cloud Init Config data to base64 format"
  cp -pr ${CLOUDINITTMP} ${CLOUDINITFILE}
echo "Get WatsCloud Pass for Object Store"
  OBJPASS=`cat   ${SCRIPT_DIR}/templates/${OBJ_PASS}`
  cp -pr ${CLOUDINITTMP} ${CLOUDINITFILE}
  sed -i -e  "s|ROOTPASS|${ROOTPASS}|g"  ${CLOUDINITFILE}
  sed -i -e  "s|APXNAME|${APXVMNAME}|g"  ${CLOUDINITFILE}
  sed -i -e  "s|OBJPASS|${OBJPASS}|g"  ${CLOUDINITFILE}
  sed -i -e  "s|OBJSTANDARD|${OBJ_STANDARD}|g"  ${CLOUDINITFILE}
  sed -i -e  "s|OBJMOUNT|${OBJ_MOUNT}|g"  ${CLOUDINITFILE}
  sed -i -e  "s|NAMESPACE|${NAMESPACE}|g"  ${CLOUDINITFILE}
  sed -i -e  "s|REGION|${REGION}|g"  ${CLOUDINITFILE}
  sed -i -e  "s|BROWSERS|${BROWSERS}|g"  ${CLOUDINITFILE}
   sed -i -e  "s|NODEEXPLORER|${NODEEXPLOREREXE}|g"  ${CLOUDINITFILE}
  sed -i -e  "s|GATEWAYURL|${GATEWAYURL}|g"  ${CLOUDINITFILE}


  CLOUDINIT=`base64 ${CLOUDINITFILE} -w 0`
  # REPLACE VARIABLES IN TEMPLATES SECTION
  echo "Updating Config File"
  sed -i -e  "s|VMCOMPID|${watscompid}|g"  ${IC_JSON_FILE}
  sed -i -e  "s|ICNAME|${IC_NAME}|g"  ${IC_JSON_FILE}
  sed -i -e  "s|CLOUDINIT|${CLOUDINIT}|"  ${IC_JSON_FILE}
  sed -i -e  "s|SSHKEY|${SSH_KEY}|g"  ${IC_JSON_FILE}
  sed -i -e  "s|UBIMGID|${UBimageOCID}|g"  ${IC_JSON_FILE}
  sed -i -e  "s|SHAPENAME|${UBVMSHAPE}|g"  ${IC_JSON_FILE}
  sed -i -e  "s|CPUCOUNT|${CPUCOUNT}|g"  ${IC_JSON_FILE}
  sed -i -e  "s|MEMORY|${MEMORY}|g"  ${IC_JSON_FILE}

  oci compute-management instance-configuration create --from-json file://${IC_JSON_FILE}
  sleep 5
  echo "IC Verifying creation status"
  STATUS=`oci compute-management instance-configuration list -c ${watscompid} --all --query "data [?\"display-name\"=='${IC_NAME}'].{NAME:\"display-name\"}" | grep NAME | awk -F'[\"|\"]' '{print $4}'`
  if [ "${STATUS}" = "${IC_NAME}" ];
  then
    echo "Instance Configuration $IC_NAME created successfully. ."
    echo "ONE" > ${EXIT_FILE}
    echo "Hi,\n\nInstance Configuration ${IC_NAME} has been created successfully. Proceeding with Instance Pool creation.\n\nRegards,\nOCI." | mail -r "${FROM_ADDRESS}" -s "OCI:Instance Config ${IC_NAME} is success " ${NOTIFY_ADDRESS}
    exit_code=`cat $EXIT_FILE 2>&1`

  else
    echo "Instance Configuration $IC_NAME creation failed."
    echo "Hi,\n\nInstance Configuration ${IC_NAME} creation Failed .\n\nRegards,\nOCI." | mail -r "${FROM_ADDRESS}" -s "OCI ERROR: Instance Config ${IC_NAME} Creation Failed " ${NOTIFY_ADDRESS}
    exit 1;
  fi;
fi;

# GET IC OCID
ICOCID_NEW=`oci compute-management instance-configuration list -c ${watscompid} --all --query "data [?\"display-name\"=='${IC_NAME}'].{OCID:\"id\"}" | grep OCID | awk -F'[\"|\"]' '{print $4}'`



# Create Instance Pool for Ubuntu
if [ "$exit_code" = "ONE" ];
then
  echo "UPDAE NEW Instance Configuration for INSTANCE POOL $IP_NAME}"
  echo
  sleep 3
  
  echo "oci compute-management instance-pool update --instance-pool-id ${IPOOLOCID} --force --instance-configuration-id ${ICOCID_NEW} --wait-for-state RUNNING"
  oci compute-management instance-pool update --instance-pool-id ${IPOOLOCID} --force --instance-configuration-id ${ICOCID_NEW} --wait-for-state RUNNING
  echo "Instance Pool verifying update status"
  STATUS=`oci compute-management instance-pool list -c ${watscompid} --all --query "data [?\"display-name\"=='${IP_NAME}'].{STATUS:\"lifecycle-state\"}" | grep STATUS | awk -F'[\"|\"]' '{print $4}'`


  if [ "${STATUS}" = "RUNNING" ];
  then
    echo "Instance Pool $IP_NAME updated successfully. ."
    echo "FOUR" > ${EXIT_FILE}
    echo "Hi,\n\nInstance Pool ${IP_NAME} has been updated successfully.\n\nRegards,\nOCI." | mail -r "${FROM_ADDRESS}" -s "OCI:Instance Pool ${IP_NAME} update is success " ${NOTIFY_ADDRESS}
    exit_code=`cat $EXIT_FILE 2>&1`

  else
    echo "Instance Pool $IP_NAME updation failed."
    echo "Hi,\n\nInstance Pool ${IP_NAME} updation Failed .\n\nRegards,\nOCI." | mail -r "${FROM_ADDRESS}" -s "OCI ERROR: Instance Pool ${IP_NAME} updation Failed " ${NOTIFY_ADDRESS}
    exit 1;
  fi;
fi;


echo
echo
echo "ZERO" > ${EXIT_FILE}
