#!/bin/sh

# Requires installed jq and 1Password CLI
# In 1Password following structure is assumed:
# - Private key uploaded as Document
# - Public key uploaded as Document
# - Container Item of type "Secure Note"
#   - Content for SSH config file in field notes
#   - Section with name "config"
#     - Field with name "path" and value with relative path without leading "/"
#   - Tags: ssh-container
#   - Private and public key referenced as file

SHORTHAND=
VAULT=
DELETE_SSH=
SESSION=

SEC_NOTE="Secure Note" # 1Password type for secure notes
SSH_TAG="ssh-container"
SSH_DIR=$HOME/.ssh

JQ_TITLE='.overview.title'
JQ_NOTES='.details.notesPlain'
JQ_FILES='(.details.sections[] | select(.name == "linked items").fields) | try map({id: .v, name: .t})'
JQ_FILE_PATH='(.details.sections[] | try select(.title == "config").fields[]) | select(.t == "path").v'

remove_ssh_content(){
  # Remove existing content
  rm -rf $SSH_DIR/*
}

create_ssh_dir(){
  # Create ssh folder if not existing
  if [ ! -d $SSH_DIR ]; then
    mkdir $SSH_DIR
    chmod 700 $SSH_DIR
  fi
}

create_ssh_sub_dir(){
  local sub_path=$1

  # Create SSH sub folders
  if [ ! -d $sub_path ]; then
    mkdir -p $sub_path
    chmod 700 $sub_path
  fi
}

create_ssh_base(){
  create_ssh_dir

  # Create basic files
  touch $SSH_DIR/authorized_keys
  chmod 600 $SSH_DIR/authorized_keys

  touch $SSH_DIR/known_hosts
  chmod 600 $SSH_DIR/known_hosts

  echo "" > $SSH_DIR/config
  chmod 600 $SSH_DIR/config
}

login(){
  # Check if login is necessary
  local SESSION_VAR_NAME=OP_SESSION_$SHORTHAND
  local SESSION_TOKEN=${!SESSION_VAR_NAME}

  if [ ! -z ${!SESSION_TOKEN} ]; then
    eval $($OP_CMD signin $SHORTHAND)
  fi
}

download_file(){
  local file_cfg=$1
  local out_path=$2
  # Get file ID for download
  local file_id=`echo $file_cfg | $JQ_CMD -r '.id'`
  # Get file name
  local file_name=`echo $file_cfg | $JQ_CMD -r '.name'`
  
  # Download file
  $OP_CMD get document $file_id --output $out_path/$file_name --session $SESSION

  # Set permissions for downloaded files
  if [[ $file_name == "*\.pub" ]]; then
    chmod 644 $out_path/$file_name
  else 
    chmod 600 $out_path/$file_name
  fi
}

update_config_file(){
  local title=$1
  local cfg=$2
  # Add SSH configuration to config file
  echo "# $title" >> $SSH_DIR/config
  echo $cfg >> $SSH_DIR/config
  echo "" >> $SSH_DIR/config
}

process_document() {
  local doc_id=$1
  # Get SSH container document
  local raw_doc=$($OP_CMD get item $doc_id --session $SESSION | sed -e "s/\\\\n/\\\\\\\\n/g" )

  local title=`echo $raw_doc | $JQ_CMD -r "$JQ_TITLE"`
  local cfg=`echo $raw_doc | $JQ_CMD "$JQ_NOTES" | sed -e 's/"//g'`
  local files=`echo $raw_doc | $JQ_CMD -r "$JQ_FILES"`
  local path=`echo $raw_doc | $JQ_CMD -r "$JQ_FILE_PATH"`

  if [[ $path ]]; then
    out_path=$SSH_DIR/$path

    create_ssh_sub_dir $out_path

    # Download all referenced files
    for file_cfg in `echo $files | $JQ_CMD -c '.[]'`; do
      download_file $file_cfg $out_path
    done

    update_config_file "$title" "$cfg"
  fi
}

print_help(){
  printf "Usage: create-ssh [flags]"
  printf ""
  printf "Creates local SSH folder based on 1Password configuration"
  printf ""
  printf "Flags:"
  printf "  -a|--account      1Password account to use"
  printf "  -d|--delete-ssh   Delete SSH folder and recreate it"
  printf "  -v|--vault        Only SSH configurations in specified vault will be used"
  printf "  -h|--help         Print this help message"
  printf ""
}

execute(){
  local account_arg=
  local valut_arg=

  # login

  if [[ $SHORTHAND ]]; then
    account_arg="--account $SHORTHAND"
  fi
  if [[ $VAULT ]]; then
    vault_arg="--vault $VAULT"
  fi

  if [[ $DELETE_SSH ]]; then
    remove_ssh_content
  fi

  create_ssh_base

  # Fetch list of uuids of SSH container documents
  RAW_DOCS_LIST=`$OP_CMD $account_arg list items --categories "$SEC_NOTE" --tags "$SSH_TAG" $vault_arg --session $SESSION | $JQ_CMD -r '.[] | .uuid'`

  for RAW_DOC in $RAW_DOCS_LIST; do
    process_document $RAW_DOC
  done
}

for arg in "$@"
do
  #echo "Arg, $arg"
  case $arg in
    -a|--account)
    SHORTHAND=$2
    shift
    shift
    ;;
    -d|--delete-ssh)
    DELETE_SSH=1
    shift
    ;;
    -s|--session)
    SESSION=$2
    shift
    shift
    ;;
    -v|--vault)
    VAULT=$2
    shift
    shift
    ;;
    -h|--help)
    print_help
    shift
    ;;
  esac
done

execute


