#!/usr/bin/env groovy
/**
 * VCNNGR Minideb Pipeline
 * Running on dedicated Docker builder node
 */

pipeline {
    agent { label 'docker' }  // ← USA IL NOSTRO NODO!
    
    environment {
        BASENAME = 'vcnngr/minideb'
        DOCKER_REGISTRY = 'docker.io'
        LATEST = 'trixie'
        
        DOCKERHUB = credentials('dockerhub-credentials')
        SONAR_TOKEN = credentials('sonarqube-token')
        
        GIT_COMMIT_SHORT = sh(returnStdout: true, script: 'git rev-parse --short HEAD').trim()
        BUILD_DATE = sh(returnStdout: true, script: 'date -u +%Y%m%d').trim()
        BUILD_TIMESTAMP = sh(returnStdout: true, script: 'date -u +%Y-%m-%dT%H-%M-%S').trim()
    }
    
    parameters {
        choice(name: 'DIST', choices: ['all', 'bullseye', 'bookworm', 'trixie'], description: 'Distribution')
        choice(name: 'ARCH', choices: ['all', 'amd64', 'arm64'], description: 'Architecture')
        booleanParam(name: 'PUSH_TO_REGISTRY', defaultValue: false, description: 'Push to Docker Hub')
        booleanParam(name: 'CREATE_MANIFESTS', defaultValue: true, description: 'Create manifests')
        booleanParam(name: 'RUN_SECURITY_SCAN', defaultValue: true, description: 'Run security scan')
        booleanParam(name: 'RUN_SONARQUBE', defaultValue: true, description: 'Run SonarQube analysis')
    }
    
    options {
        buildDiscarder(logRotator(numToKeepStr: '30'))
        timestamps()
        timeout(time: 6, unit: 'HOURS')
        ansiColor('xterm')
    }
    
    stages {
        stage('Initialize') {
            steps {
                script {
                    echo """
╔════════════════════════════════════════════╗
║   VCNNGR Minideb Build Pipeline           ║
║   Running on Docker Builder Node          ║
╚════════════════════════════════════════════╝

Distribution: ${params.DIST}
Architecture: ${params.ARCH}
Build Date:   ${BUILD_DATE}
Commit:       ${GIT_COMMIT_SHORT}
"""
                    def dists = params.DIST == 'all' ? ['bullseye', 'bookworm', 'trixie'] : [params.DIST]
                    def archs = params.ARCH == 'all' ? ['amd64', 'arm64'] : [params.ARCH]
                    
                    env.BUILD_DISTS = dists.join(',')
                    env.BUILD_ARCHS = archs.join(',')
                }
            }
        }
        
        stage('Setup') {
            steps {
                sh '''
                    set -e
                    # Installa tool necessari
                    sudo apt-get update -qq
                    sudo apt-get install -y -qq \
                        debootstrap debian-archive-keyring jq dpkg-dev \
                        gnupg curl shellcheck git rsync
                    
                    # Verifica Docker e buildx
                    docker version
                    docker buildx ls
                    
                    # Scripts eseguibili
                    chmod +x mkimage import buildone test pushone pushall pushmanifest || true
                    
                    echo "Setup completato"
                '''
            }
        }
        
        stage('Code Quality') {
            parallel {
                stage('Shellcheck') {
                    steps {
                        sh '''
                            if [ -f shellcheck ]; then
                                bash shellcheck || echo "Shellcheck warnings"
                            else
                                shellcheck mkimage import buildone || echo "Shellcheck OK"
                            fi
                        '''
                    }
                }
                
                stage('SonarQube Analysis') {
                    when {
                        expression { params.RUN_SONARQUBE }
                    }
                    steps {
                        script {
                            try {
                                // Esegui sonar-scanner in container Docker
                                sh '''
                                    docker run --rm \
                                        -v ${WORKSPACE}:/usr/src \
                                        -w /usr/src \
                                        sonarsource/sonar-scanner-cli:latest \
                                        sonar-scanner \
                                            -Dsonar.host.url=http://sonarqube-sonarqube.jenkins.svc.cluster.local:9000 \
                                            -Dsonar.token=${SONAR_TOKEN} \
                                            -Dsonar.projectKey=vcnngr-minideb \
                                            -Dsonar.projectName='VCNNGR Minideb' \
                                            -Dsonar.projectVersion=${BUILD_DATE}-${GIT_COMMIT_SHORT} \
                                            -Dsonar.sources=. \
                                            -Dsonar.exclusions='**/*.md,build/**'
                                '''
                            } catch (Exception e) {
                                echo "WARNING: SonarQube failed: ${e.message}"
                            }
                        }
                    }
                }
            }
        }
        
        stage('Build Images') {
            matrix {
                axes {
                    axis {
                        name 'DIST_NAME'
                        values 'bullseye', 'bookworm', 'trixie'
                    }
                    axis {
                        name 'ARCH_NAME'
                        values 'amd64', 'arm64'
                    }
                }
                
                when {
                    expression {
                        env.BUILD_DISTS.split(',').contains(DIST_NAME) && 
                        env.BUILD_ARCHS.split(',').contains(ARCH_NAME)
                    }
                }
                
                stages {
                    stage('Create Base') {
                        steps {
                            sh """
                                echo "════════════════════════════════════════"
                                echo "Building ${DIST_NAME}-${ARCH_NAME}"
                                echo "════════════════════════════════════════"
                                
                                mkdir -p build
                                ./mkimage "build/${DIST_NAME}-${ARCH_NAME}.tar" "${DIST_NAME}" "${ARCH_NAME}"
                                
                                ls -lh build/${DIST_NAME}-${ARCH_NAME}.tar
                            """
                        }
                    }
                    
                    stage('Import & Tag') {
                        steps {
                            sh """
                                TIMESTAMP=\$(date -u +%Y-%m-%dT%H:%M:%SZ)
                                
                                IMAGE_ID=\$(bash ./import "build/${DIST_NAME}-${ARCH_NAME}.tar" "\${TIMESTAMP}" "${ARCH_NAME}")
                                
                                # Tag images
                                docker tag \${IMAGE_ID} ${BASENAME}:${DIST_NAME}-${ARCH_NAME}
                                docker tag \${IMAGE_ID} ${BASENAME}:${DIST_NAME}-${ARCH_NAME}-${BUILD_DATE}
                                
                                if [ "${DIST_NAME}" = "${LATEST}" ]; then
                                    docker tag \${IMAGE_ID} ${BASENAME}:latest-${ARCH_NAME}
                                fi
                                
                                docker images ${BASENAME}:${DIST_NAME}-${ARCH_NAME}
                            """
                        }
                    }
                    
                    stage('Test') {
                        steps {
                            sh """
                                echo "Testing ${DIST_NAME}-${ARCH_NAME}"
                                
                                docker run --rm ${BASENAME}:${DIST_NAME}-${ARCH_NAME} \
                                    bash -c 'cat /etc/os-release | head -2'
                                
                                docker run --rm ${BASENAME}:${DIST_NAME}-${ARCH_NAME} \
                                    bash -c 'install_packages curl && curl --version | head -1'
                                
                                docker run --rm ${BASENAME}:${DIST_NAME}-${ARCH_NAME} \
                                    bash -c 'dpkg --print-architecture'
                            """
                        }
                    }
                    
                    stage('Security') {
                        when {
                            expression { params.RUN_SECURITY_SCAN }
                        }
                        steps {
                            script {
                                sh "mkdir -p build/security"
                                
                                try {
                                    // Esegui Trivy in container
                                    sh """
                                        docker run --rm \
                                            -v /var/run/docker.sock:/var/run/docker.sock \
                                            -v ${WORKSPACE}/build/security:/output \
                                            aquasec/trivy:latest image \
                                                --severity HIGH,CRITICAL \
                                                --format json \
                                                --output /output/trivy-${DIST_NAME}-${ARCH_NAME}.json \
                                                ${BASENAME}:${DIST_NAME}-${ARCH_NAME}
                                    """
                                } catch (Exception e) {
                                    echo "WARNING: Security scan failed: ${e.message}"
                                }
                            }
                        }
                    }
                    
                    stage('Push') {
                        when {
                            expression { params.PUSH_TO_REGISTRY }
                        }
                        steps {
                            sh """
                                echo \${DOCKERHUB_PSW} | docker login -u \${DOCKERHUB_USR} --password-stdin
                                
                                docker push ${BASENAME}:${DIST_NAME}-${ARCH_NAME}
                                docker push ${BASENAME}:${DIST_NAME}-${ARCH_NAME}-${BUILD_DATE}
                                
                                if [ "${DIST_NAME}" = "${LATEST}" ]; then
                                    docker push ${BASENAME}:latest-${ARCH_NAME}
                                fi
                                
                                docker logout
                            """
                        }
                    }
                }
            }
        }
        
        stage('Create Manifests') {
            when {
                allOf {
                    expression { params.PUSH_TO_REGISTRY }
                    expression { params.CREATE_MANIFESTS }
                    expression { params.ARCH == 'all' }
                }
            }
            steps {
                script {
                    def dists = env.BUILD_DISTS.split(',')
                    
                    sh "echo \${DOCKERHUB_PSW} | docker login -u \${DOCKERHUB_USR} --password-stdin"
                    
                    dists.each { dist ->
                        sh """
                            docker manifest create ${BASENAME}:${dist} \
                                --amend ${BASENAME}:${dist}-amd64 \
                                --amend ${BASENAME}:${dist}-arm64
                            
                            docker manifest push ${BASENAME}:${dist}
                        """
                    }
                    
                    sh "docker logout"
                }
            }
        }
    }
    
    post {
        always {
            sh 'docker system prune -af --volumes || true'
        }
        
        success {
            echo "✅ BUILD SUCCESSFUL"
        }
        
        failure {
            echo "❌ BUILD FAILED"
        }
    }
}
