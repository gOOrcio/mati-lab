pipeline {
    agent any

    parameters {
        choice(
                name: 'ACTION',
                choices: ['Rebuild Environment', 'Restart Containers', 'Full Redeploy'],
                description: 'Select the action to perform'
        )
    }

    environment {
        SERVER_IP = '192.168.1.148' // Replace with your server's IP
        SSH_USER = 'mateuszg' // Replace with your SSH username
        CONFIG_PATH = '/home/mateuszg/IdeaProjects/mati-lab/nixos' // Path to your NixOS configuration
    }

    stages {
        stage('Perform Action') {
            steps {
                script {
                    // Execute action based on selected choice
                    if (params.ACTION == 'Rebuild Environment') {
                        rebuildEnvironment()
                    } else if (params.ACTION == 'Restart Containers') {
                        restartContainers()
                    } else if (params.ACTION == 'Full Redeploy') {
                        fullRedeploy()
                    } else {
                        error("Unknown action: ${params.ACTION}")
                    }
                }
            }
        }
    }
}

def rebuildEnvironment() {
    echo 'Rebuilding NixOS environment...'
    sh """
        ssh ${env.SSH_USER}@${env.SERVER_IP} \
            "sudo nixos-rebuild switch -I nixos-config=${env.CONFIG_PATH}/configuration.nix"
    """
}

def restartContainers() {
    echo 'Restarting Docker containers...'
    sh """
        ssh ${env.SSH_USER}@${env.SERVER_IP} \
            "cd ${env.CONFIG_PATH}/docker && docker-compose down && docker-compose up -d"
    """
}

def fullRedeploy() {
    echo 'Performing full redeploy...'
    rebuildEnvironment()
    restartContainers()
}
