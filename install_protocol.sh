#!/bin/bash

# Set default values
username="protocol"
protocol_uid=1001
network=${1:-testnet}
node_type=${2:-full_node}
version=${3:-master}
image="maestroi/nimiq-albatross:stable"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -n $'\033[0;32m'
echo $''
echo $'     _  __ _         _         ____           __         __ __          '
echo $'    / |/ /(_)__ _   (_)___ _  /  _/___   ___ / /_ ___ _ / // /___  ____ '
echo $'   /    // //  " \ / // _ `/ _/ / / _ \ (_-</ __// _ `// // // -_)/ __/ '
echo $'  /_/|_//_//_/_/_//_/ \_, / /___//_//_//___/\__/ \_,_//_//_/ \__//_/    '
echo $'                       /_/                                              '
echo $' \033[0m';
echo -e "${BLUE}Installing Nimiq with node type $node_type on $network network.${NC}"

# Check if the script is running as root
if [[ $(id -u) -ne 0 ]]; then
    echo -e "${YELLOW}This script must be run as root.${NC}"
    exit 1
fi

# Check if the OS is Ubuntu
if [[ $(lsb_release -si) != "Ubuntu" ]]; then
    echo -e "${YELLOW}This script is only compatible with Ubuntu.${NC}"
    exit 1
fi

# Function to install a Nimiq full node
function install_full_node() {
    # Download Docker Compose file
    echo -e "${GREEN}Downloading Docker Compose file full node.${NC}"
    curl -sSL https://raw.githubusercontent.com/maestroi/nimiq-installer/$version/full_node/Docker-compose.yaml -o /opt/nimiq/configuration/docker-compose.yaml

    # Download Nginx configuration file
    echo -e "${GREEN}Downloading Nginx configuration file.${NC}"
    curl -sSL https://raw.githubusercontent.com/maestroi/nimiq-installer/$version/full_node/nginx.conf -o /opt/nimiq/configuration/default.conf
    
    ufw allow 80/tcp &>/dev/null

    # Download config files
    if [ "$network" == "testnet" ]; then
        echo -e "${GREEN}Downloading config file: testnet-config.toml.${NC}"
        curl -s https://raw.githubusercontent.com/maestroi/nimiq-installer/$version/full_node/testnet-config.toml -o /opt/nimiq/configuration/client.toml
    elif [ "$network" == "mainnet" ]; then
        echo -e "${GREEN}Downloading config file: mainnet-config.toml.${NC}"
        curl -s https://raw.githubusercontent.com/maestroi/nimiq-installer/$version/full_node/mainnet-config.toml -o /opt/nimiq/configuration/client.toml
    else
        echo -e "${YELLOW}Invalid network parameter. Please use testnet or mainnet.${NC}"
        exit 1
    fi
}

# Function to install a Nimiq valdator node
function install_validator() {
    # Set variables
    address="/opt/nimiq/secrets/address.txt"
    fee_key="/opt/nimiq/secrets/fee_key.txt"
    signing_key="/opt/nimiq/secrets/signing_key.txt"
    vote_key="/opt/nimiq/secrets/vote_key.txt"

    # Download Docker Compose file
    echo -e "${GREEN}Downloading Docker Compose file validator node.${NC}"
    curl -sSL https://raw.githubusercontent.com/maestroi/nimiq-installer/$version/validator/Docker-compose.yaml -o /opt/nimiq/configuration/docker-compose.yaml

    # Create nimiq address secrets
    echo -e "${GREEN}Generate nimiq address secrets.${NC}"
    generate_nimiq_address $address

    # Generate fee key
    echo -e "${GREEN}Generate Fee key secrets.${NC}"
    generate_nimiq_address $fee_key

    # Generate signing key
    echo -e "${GREEN}Generate signing key secrets.${NC}"
    generate_nimiq_address $signing_key

    # Create nimiq bls secrets
    echo -e "${GREEN}Generate nimiq bls secrets.${NC}"
    generate_nimiq_bls $vote_key

    # Download config files
    if [ "$network" == "testnet" ]; then
        echo -e "${GREEN}Downloading config file: testnet-config.toml.${NC}"
        curl -s https://raw.githubusercontent.com/maestroi/nimiq-installer/$version/validator/testnet-config.toml -o /opt/nimiq/configuration/client.toml
    elif [ "$network" == "mainnet" ]; then
        echo -e "${GREEN}Downloading config file: mainnet-config.toml.${NC}"
        curl -s https://raw.githubusercontent.com/maestroi/nimiq-installer/$version/validator/mainnet-config.toml -o /opt/nimiq/configuration/client.toml
    else
        echo -e "${YELLOW}Invalid network parameter. Please use testnet or mainnet.${NC}"
        exit 1
    fi

    #Set paths
    configuration_file="/opt/nimiq/configuration/client.toml"
    # Read values from /opt/nimiq/secrets/nimiq-address.txt
    ADDRESS=$(cat $address | sed -n 's/Address:[[:space:]]*\(.*\)/\1/p')
    ADDRESS_PRIVATE=$(grep "Private Key:" $address | awk '{print $3}')
    FEE_KEY=$(grep "Private Key:" $fee_key | awk '{print $3}')
    SIGNING_KEY=$(grep "Private Key:" $signing_key | awk '{print $3}')
    VOTING_KEY=$(awk '/Secret Key:/{getline; getline; print}' $vote_key)

    # Update client.toml
    sed -i "s/CHANGE_VALIDATOR_ADDRESS/$ADDRESS/g" $configuration_file
    sed -i "s/CHANGE_FEE_KEY/$FEE_KEY/g" $configuration_file
    sed -i "s/CHNAGE_SIGN_KEY/$SIGNING_KEY/g" $configuration_file
    sed -i "s/CHANGE_VOTE_KEY/$VOTING_KEY/g" $configuration_file
}

# Function to install the Nimiq protocol installer script
function install_protocol_script() {
    # Set the script name
    script_name="nimiq-update"

    # Set the script URL
    script_url="https://raw.githubusercontent.com/maestroi/nimiq-installer/$version/install_protocol.sh"

    # Set the destination directory
    destination_dir="/usr/local/bin"

    # Set the full path to the script
    script_path="$destination_dir/$script_name"

    # Define the command to run
    cmd="curl -sSL $script_url | bash -s $network $node_type"

    # Create the script file
    echo -e "${GREEN}Creating the Nimiq installer script in $script_path.${NC}"
    echo "#!/bin/bash" > $script_path
    echo "# Download and run the Nimiq protocol installer script with the specified network and node type" >> $script_path
    echo $cmd >> $script_path

    # Make the script executable
    echo -e "${GREEN}Making the Nimiq installer script executable.${NC}"
    chmod +x $script_path

    # Display a success message
    echo -e "${GREEN}The Nimiq installer script has been installed successfully.${NC}"
}

# Function to generate a Nimiq address
function generate_nimiq_address() {
    # Set the path to the output file
    output_file="/opt/nimiq/secrets/nimiq-address.txt"

    # Check if an output file parameter was passed and set the output file path accordingly
    if [ "$1" != "" ]; then
        output_file=$1
    fi

    # Check if the output file already exists
    if [ -f $output_file ]; then
        echo -e "${YELLOW}The file $output_file already exists.${NC}"
    else
        # Create the Docker container and run the command
        docker run --rm --name nimiq-address $image nimiq-address > $output_file 2>/dev/null
    fi
}

# Function to generate a Nimiq address
function generate_nimiq_bls() {
    # Set the path to the output file
    output_file="/opt/nimiq/secrets/votekey.txt"

    # Check if an output file parameter was passed and set the output file path accordingly
    if [ "$1" != "" ]; then
        output_file=$1
    fi

    # Check if the output file already exists
    if [ -f $output_file ]; then
        echo -e "${YELLOW}The file $output_file already exists.${NC}"
    else
        # Create the Docker container and run the command
        echo -e "${GREEN}Generating a new Nimiq address.${NC}"
        docker run --rm --name nimiq-address $image nimiq-bls > $output_file 2>/dev/null
    fi
}

function activate_validator(){
    echo -e "${GREEN}Downloading validator activator${NC}"
    curl -sSL https://raw.githubusercontent.com/maestroi/nimiq-installer/$version/validator/activate_validator.py -o /opt/nimiq/bin/activate_validator.py

    echo -e "${GREEN}Install requirements for script${NC}"
    pip install requests

    chmod +x /opt/nimiq/bin/activate_validator.py
    python3 /opt/nimiq/bin/activate_validator.py --private-key=/opt/nimiq/secrets/address.txt
}


# Create the protocol group with the specified GID (if it does not already exist)
if ! getent group $protocol_uid &>/dev/null; then
    echo -e "${GREEN}Creating group: $protocol_uid.${NC}"
    groupadd -r -g $protocol_uid $username
fi

# Check if the user protocol exists, and create it if it doesn't
if ! id -u $username > /dev/null 2>&1; then
    echo -e "${GREEN}Creating user: $username with ID: $protocol_uid .${NC}"
    id -u $username &>/dev/null || useradd -r -m -u $protocol_uid -g $protocol_uid -s /usr/sbin/nologin $username

fi

# Update and upgrade Ubuntu
echo -e "${GREEN}Updating and upgrading Ubuntu, may take a while....${NC}"
apt-get update &>/dev/null
apt-get upgrade -y &>/dev/null

# Install Docker and Docker Compose
echo -e "${GREEN}Installing Docker and Docker Compose.${NC}"
apt-get install -y docker.io docker-compose python3 python3-pip &>/dev/null

# Install some common packages
echo -e "${GREEN}Installing common packages.${NC}"
apt-get install -y curl jq libjq1 libonig5 git ufw fail2ban &>/dev/null

# Check if the protocol user is already in the docker group, and add it if it's not
if ! id -nG $username | grep -qw docker; then
    echo -e "${GREEN}Adding user $username to the docker group.${NC}"
    usermod -aG docker $username
fi

# Check if the directories already exist, and create them if they don't
if [ ! -d "/opt/nimiq/configuration" ]; then
    echo -e "${GREEN}Creating directory: /opt/nimiq/configuration.${NC}"
    mkdir -p /opt/nimiq/configuration
fi

if [ ! -d "/opt/nimiq/data" ]; then
    echo -e "${GREEN}Creating directory: /opt/nimiq/data.${NC}"
    mkdir -p /opt/nimiq/data
fi

if [ ! -d "/opt/nimiq/secrets" ]; then
    echo -e "${GREEN}Creating directory: /opt/nimiq/secrets.${NC}"
    mkdir -p /opt/nimiq/secrets
fi

if [ ! -d "/opt/nimiq/bin" ]; then
    echo -e "${GREEN}Creating directory: /opt/nimiq/bin.${NC}"
    mkdir -p /opt/nimiq/bin
fi

# Set permissions for the directories
echo -e "${GREEN}Setting permissions for directories.${NC}"
chown -R $protocol_uid:$protocol_uid /opt/nimiq/configuration /opt/nimiq/data /opt/nimiq/secrets /opt/nimiq/bin
chmod -R 750 /opt/nimiq/configuration
chmod -R 755 /opt/nimiq/data
chmod -R 740 /opt/nimiq/secrets
chmod -R 755 /opt/nimiq/bin

#Set the RPC_ENABLED environment variable based on the node type
if [ "$node_type" == "full_node" ]; then
    echo -e "${GREEN}Installing Full node.${NC}"
    install_full_node
elif [ "$node_type" == "validator" ]; then
    echo -e "${GREEN}Installing validator.${NC}"
    install_validator
else
    echo -e "${YELLOW}Invalid node_type parameter. Please use full_node or validator.${NC}"
    exit 1
fi

echo -e "${GREEN}Installing Nimiq update script${NC}"
install_protocol_script

# Add firewall rules to allow incoming traffic on ports 80, 22, and 8443
echo -e "${GREEN}Adding firewall rules.${NC}"
ufw --force enable &>/dev/null
ufw allow 22/tcp &>/dev/null
ufw allow 8443/tcp &>/dev/null
ufw allow 8443/udp &>/dev/null
echo -e "${GREEN}UFW configured successfully.${NC}"

# Run the Docker container using Docker Compose
echo -e "${GREEN}Starting Docker container.${NC}"
cd /opt/nimiq/configuration
docker-compose down &>/dev/null
docker-compose up -d &>/dev/null
echo -e "${GREEN}-----------------${NC}"
echo -e "${GREEN}To restart containers navigate /opt/nimiq/configuration and run docker-compose restart ${NC}"
echo -e "${GREEN}Follow logs with: docker-compose logs ${NC}"
echo -e "${GREEN}-----------------${NC}"

if [ "$node_type" == "full_node" ]; then
    # Get the public IP address
    public_ip=$(curl -s https://api.ipify.org)
    # Display the public IP address
    echo -e "${GREEN}The Nimiq node is now running at: http://$public_ip${NC}"
fi

if [ "$node_type" == "validator" ]; then
    # Activate validator
    activate_validator
    echo -e "${GREEN}The Validator node is now running and active{NC}"
fi

# Print a message indicating that the script has finished
echo -e "${GREEN}For any help navigate to: https://github.com/maestroi/nimiq-installer ${NC}"
echo -e "${GREEN}The script has finished.${NC}"
