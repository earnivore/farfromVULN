#!/bin/bash

# Text constants
MAGENTA='\e[95m'
NC='\033[0m'
BOLD='\e[1m'
NORMAL='\e[21m'
RED='\e[91m'
EXIT='echo -e \e[91m\e[1m'

upload_image() {
    # Get function arguments
    file_name=$1
    file_type=$2

    # Upload process begins here
    # Get file type
    if [[ $file_type == "" ]]; then
	file_type=$(echo $file_name | cut -d'.' -f 2)
    fi
    echo "File type detected: $file_type"


    echo "Enter AWS profile with S3 Bucket permissions: "
    echo -n "> "
    read S3_USER
    

    echo "Uploading to AWS..."
    aws s3 cp vulnhub_ovas/$file_name s3://vmstorage/ --profile $S3_USER

    # Check if upload cancelled, and if so, exit program
    if [[ $? -eq 1 ]]
    then
	clean_up
	echo "Upload failed. Exiting now..."
	exit 1
    fi

    echo "Enter AWS profile with Image Upload permissions: "
    echo -n "> "
    read IMG_UPLOAD_USER
    
    # Import image based on type of file it is
    # TODO: Add name tags
    aws ec2 import-image --disk-containers Format=$file_type,UserBucket="{S3Bucket=vmstorage,S3Key=$file_name}" --profile $IMG_UPLOAD_USER --region us-east-2 > import_ami_task.txt

    # Get the AMI ID of the image
    ami=$(grep import import_ami_task.txt | cut -d'"' -f 4)
    echo "AMI ID of the uploaded image: $ami"

    echo "aws ec2 describe-import-image-tasks --import-task-ids $task_id"

    # Loop and check when the upload process has completed
    # TODO: Check if upload failed and exit script
    flag=false
    start=$SECONDS
    while [ $flag != true ]
    do
	duration=$(( SECONDS - start ))
	echo "Checking for completion on image upload...  [ $duration seconds elapsed ]" 
	sleep 30

	aws ec2 describe-import-image-tasks --import-task-ids $ami > import_ami_task.txt
	
	# Check for failure
	FAILURE=$(grep deleting ./import_ami_task.txt | wc -l)
	if [[ $FAILURE > 0 ]]
	then
	    FAILURE_MSG=$(grep StatusMessage ./import_ami_task.txt)	    
	    clean_up
	    echo "Image is not compatible for the AWS Image Import process. Exiting now..."
	    echo "$FAILUREMSG"
	    echo "Removing downloaded file..."
	    rm ./vulnhub_ovas/$file_name
	    exit 1
	fi
	
	# Check for success
	check=$(grep completed ./import_ami_task.txt | wc -l)
	if [[ $check == 2 ]]
	then
	    flag=true
	    echo "Process has completed!"
	fi
    done

    # Apply to Terraform, should also build a .tf file with the new AMI uploaded
    vuln_path="./vulnerable_machines/$search_machine"
    suffix=".tf"
    final_path="$vuln_path$suffix"
    echo -n """
# A Vulnhub machine on the network
resource \"aws_instance\" \"$search_machine\" {
  ami                    = \"$ami\" # Custom AMI, uploaded using https://docs.amazonaws.cn/en_us/vm-import/latest/userguide/vm-import-ug.pdf
  instance_type          = var.instance_type
  key_name               = \"primary\"
  subnet_id              = aws_subnet.my_subnet.id
  vpc_security_group_ids = [aws_security_group.allow_vuln.id]

  tags = {
    Name = \"$search_machine\"
  }
}
""" > $final_path

    # Copy to main directory to be part of Terraform deploy
    cp $final_path .

    echo "Vulnhub image successfully uploaded to AWS and ready for deployment!"
    
}

clean_up() {
    ${EXIT}
    # Clean up all the files we create
    rm machine_choices.txt 2> /dev/null
    rm checksum.txt 2> /dev/null
    rm import_ami_task.txt 2> /dev/null
}

clean_up

clear

echo -e "${MAGENTA}${BOLD}Welcome to farfromVULN"

cat farfromVULN.logo

# Pick a vulnhub machine to deploy
COUNTER=0
MACHINES=$(find ./vulnerable_machines/ | cut -d'/' -f 3)
echo "Pick a Vulnhub machine to deploy:"
for MACHINE in $MACHINES
do
    MACHINE=$(echo $MACHINE | cut -d'.' -f 1)
    COUNTER=$((COUNTER+1))
    echo "($COUNTER) $MACHINE"
    echo "$COUNTER.$MACHINE" >> machine_choices.txt
done
COUNTER=$((COUNTER+1))
echo "($COUNTER) Search for Vulnhub machine"
echo "$COUNTER.Search" >> machine_choices.txt

COUNTER=$((COUNTER+1))
echo "($COUNTER) Import local Vulnhub image"
echo "$COUNTER.Import" >> machine_choices.txt

# Default color and font
echo -e "${NORMAL}${NC}"

# read in the choice
echo -n "> "
read vuln_choice

# Loop through and find the machine the user selected
while IFS= read -r line;
do
    NUM=$(echo $line | cut -d'.' -f 1)
    if [[ $vuln_choice =~ $NUM ]]
    then
	SELECTED_MACHINE=$(echo $line | cut -d'.' -f 2)

	# TODO: Add import functionality
	# To import an image, store the image in ./vulnhub_ovas/ directory
	if [[ $SELECTED_MACHINE =~ "Import" ]]
	then
	    echo "What file do you want to import?"
	    echo -n "> "
	    read IMPORT_FILE </dev/tty
	    IMPORT_FILE_TYPE=$(echo $IMPORT_FILE | cut -d'.' -f 2)
	    upload_image $IMPORT_FILE $IMPORT_FILE_TYPE

	    
	    # If the user chose to search, then begin search functionality
	elif [[ $SELECTED_MACHINE =~ "Search" ]]
	then
	    echo -n "Vulnhub machine to search for: "
	    read search_machine </dev/tty
	    wget -q https://download.vulnhub.com/checksum.txt
	    VAL=$(grep -i -m 1 $search_machine checksum.txt | cut -d' ' -f 3)
	    CHECKSUM=$(grep -i -m 1 $search_machine checksum.txt | cut -d' ' -f 1)	    
	    file_name=$(echo "$VAL" | rev | cut -d'/' -f 1 | rev)
	    VAL2="https://download.vulnhub.com/"
	    VAL3="$VAL2$VAL"
	    echo "Found file at $VAL3"

	    wget --spider $VAL3
	    echo "Are you sure you want to download this file? (y/n)"
	    echo -n "> "
	    read confirm </dev/tty
	    if [[ $confirm = "y" ]]
	    then
		rm checksum.txt
		echo "Retrieving file..."
		wget --directory-prefix=./vulnhub_ovas/ $VAL3

		# Confirm successful download with checksum		
		COMPARE=$(md5sum ./vulnhub_ovas/$file_name | cut -d' ' -f 1)		
		echo "COMPARE: $COMPARE"
		echo "CHECKSUM: $CHECKSUM"

		if [[ $COMPARE != $CHECKSUM ]]
		then
		    echo "ERROR: Downloaded file did not match download checksum. Exiting now and removing the downloaded file."
		    rm ./vulnhub_ovas/$file_name
		    clean_up
		    exit 1
		fi
		
		# TODO: Account for different compression file types
		# Regex check to see if its a zip file
		if [[ $file_name =~ "zip" ]];
		then
		    unzip ./vulnhub_ovas/$file_name -d ./vulnhub_ovas/
		    # From here we need to regex and find a compatible file type,
		    # then set that file type as the new file name for upload
		    file_name=$(find ./vulnhub_ovas | grep -E "ova|vmdk" -m 1)

		    # If no ova or vmdk file is found, then exit the importation process
		    if [[ $file_name == "./vulnhub_ovas" ]]
		    then
			clean_up			
			echo "The file is not in a compatible file format and cannot be imported in AWS. Exiting now."
			exit 1
		    fi
		    file_type=$(echo $file_name | cut -d'.' -f 3)	    
		fi
	    elif [[ $confirm = "n" ]]
	    then
		clean_up
		echo "bye!"
		exit 1
	    fi

	    # upload the image to AWS
	    upload_image $file_name $file_type

	else
	    cp vulnerable_machines/$SELECTED_MACHINE.tf .
	    echo "Adding $SELECTED_MACHINE to lab build..."
	fi
    fi
done < machine_choices.txt

echo "Building machine now..."

terraform apply

if [[ $? -eq 0 ]]
then
    terraform output -json > instance_ips.txt
    
    # Get the public IP of the PiVPN server
    VPN_PUB_IP=$(grep -A 3 PiVPN instance_ips.txt | grep value | cut -d"\"" -f 4)
    # Give the web app the correct VPC private ips
    
    echo yes | scp  -i "~/.ssh/labs-key.pem" instance_ips.txt ubuntu@$VPN_PUB_IP:/home/ubuntu/

    # Start the web app! Hosted on port 7894
    echo "Now starting web application..."
    ssh -i "~/.ssh/labs-key.pem" ubuntu@$VPN_PUB_IP "export FLASK_APP=/home/ubuntu/app.py && flask run -h 0.0.0.0 -p 7894"
else
    clean_up
    echo "Terraform deployment failed. Now exiting..."
    exit 1
fi

