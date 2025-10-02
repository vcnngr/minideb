// VCNNGR MinidEB Pipeline - Production with SonarQube
// Fixed: workspace path issues and script execution

pipeline {
    agent {
        kubernetes {
            yaml """
apiVersion: v1
kind: Pod
metadata:
  labels:
    jenkins: agent
    job: vcnngr-minideb
spec:
  serviceAccountName: jenkins-agent
  securityContext:
    runAsUser: 0
    fsGroup: 0
  volumes:
  - name: docker-sock
    hostPath:
      path: /var/run/docker.sock
      type: Socket
  containers:
  - name: debian
    image: debian:bookworm
    command: [cat]
    tty: true
    securityContext:
      privileged: true
    resources:
      requests:
        memory: "4Gi"
        cpu: "2000m"
      limits:
        memory: "8Gi"
        cpu: "4000m"
    volumeMounts:
    - name: docker-sock
      mountPath: /var/run/docker.sock
    env:
    - name: DEBIAN_FRONTEND
      value: noninteractive
  - name: docker
    image: docker:24-cli
    command: [cat]
    tty: true
    volumeMounts:
    - name: docker-sock
      mountPath: /var/run/docker.sock
  - name: trivy
    image: aquasec/trivy:latest
    command: [cat]
    tty: true
    volumeMounts:
    - name: docker-sock
      mountPath: /var/run/docker.sock
"""
        }
    }
    
    environment {
        BASENAME = 'vcnngr/minideb'
        DOCKER_REGISTRY = 'docker.io'
        LATEST = 'trixie'
        
        DOCKERHUB = credentials('dockerhub-credentials')
        
        GIT_COMMIT_SHORT = sh(returnStdout: true, script: 'git rev-parse --short HEAD').trim()
        BUILD_DATE = sh(returnStdout: true, script: 'date -u +%Y%m%d').trim()
        BUILD_TIMESTAMP = sh(returnStdout: true, script: 'date -u +%Y%m%d-%H%M%S').trim()
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
║   VCNNGR MinidEB Build Pipeline           ║
║   Based on Bitnami MinidEB                 ║
╚════════════════════════════════════════════╝

Distribution: ${params.DIST}
Architecture: ${params.ARCH}
Build Date:   ${BUILD_DATE}
Commit:       ${GIT_COMMIT_SHORT}
Workspace:    ${env.WORKSPACE}
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
                container('debian') {
                    sh '''
                        apt-get update -qq
                        apt-get install -y -qq \
                            debootstrap debian-archive-keyring jq dpkg-dev \
                            gnupg curl shellcheck git rsync qemu-user-static unzip
                        
                        # Ensure scripts are executable
                        chmod +x mkimage import buildone test pushone pushall pushmanifest
                    '''
                }
                container('docker') {
                    sh '''
                        docker run --rm --privileged multiarch/qemu-user-static --reset -p yes || true
                        docker buildx create --use --name vcnngr-builder || docker buildx use vcnngr-builder || true
                    '''
                }
            }
        }
        
        stage('Code Quality') {
            parallel {
                stage('Shellcheck') {
                    steps {
                        container('debian') {
                            sh 'bash shellcheck'
                        }
                    }
                }
                
                stage('SonarQube') {
                    when {
                        expression { params.RUN_SONARQUBE }
                    }
                    steps {
                        container('debian') {
                            script {
                                try {
                                    withSonarQubeEnv('SonarQube') {
                                        sh '''
                                            curl -sSLo /tmp/sonar-scanner.zip \
                                                https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-cli-5.0.1.3006-linux.zip
                                            unzip -q /tmp/sonar-scanner.zip -d /opt
                                            
                                            /opt/sonar-scanner-*/bin/sonar-scanner \
                                                -Dsonar.projectKey=vcnngr-minideb \
                                                -Dsonar.projectName='VCNNGR MinidEB' \
                                                -Dsonar.projectVersion=${BUILD_DATE}-${GIT_COMMIT_SHORT} \
                                                -Dsonar.sources=. \
                                                -Dsonar.exclusions='**/*.md,build/**,**/.github/**,**/.git/**' \
                                                -Dsonar.sourceEncoding=UTF-8
                                        '''
                                    }
                                } catch (Exception e) {
                                    echo "WARNING: SonarQube failed: ${e.message}"
                                }
                            }
                        }
                    }
                }
            }
        }
        
        stage('Quality Gate') {
            when {
                expression { params.RUN_SONARQUBE }
            }
            steps {
                timeout(time: 10, unit: 'MINUTES') {
                    script {
                        try {
                            def qg = waitForQualityGate()
                            if (qg.status != 'OK') {
                                echo "WARNING: Quality Gate ${qg.status} - continuing anyway"
                            }
                        } catch (Exception e) {
                            echo "WARNING: Quality Gate check failed - continuing anyway"
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
                            container('debian') {
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
                    }
                    
                    stage('Import & Tag') {
                        steps {
                            container('docker') {
                                sh """
                                    set -e
                                    
                                    echo "Importing ${DIST_NAME}-${ARCH_NAME}"
                                    cd \${WORKSPACE}
                                    
                                    TIMESTAMP=\$(date -u +%Y-%m-%dT%H:%M:%S.%NZ)
                                    
                                    if docker pull ${BASENAME}:${DIST_NAME}-${ARCH_NAME} 2>/dev/null; then
                                        TIMESTAMP=\$(docker inspect ${BASENAME}:${DIST_NAME}-${ARCH_NAME} | jq -r '.[0].Created')
                                        echo "Using existing timestamp: \${TIMESTAMP}"
                                    fi
                                    
                                    # Execute import script with bash
                                    IMAGE_ID=\$(bash ./import "build/${DIST_NAME}-${ARCH_NAME}.tar" "\${TIMESTAMP}" "${ARCH_NAME}")
                                    
                                    if [ -z "\${IMAGE_ID}" ]; then
                                        echo "ERROR: Failed to import image"
                                        exit 1
                                    fi
                                    
                                    echo "Image ID: \${IMAGE_ID}"
                                    
                                    docker tag \${IMAGE_ID} ${BASENAME}:${DIST_NAME}-${ARCH_NAME}
                                    docker tag \${IMAGE_ID} ${BASENAME}:${DIST_NAME}-${ARCH_NAME}-${BUILD_DATE}
                                    
                                    if [ "${DIST_NAME}" == "${LATEST}" ]; then
                                        docker tag \${IMAGE_ID} ${BASENAME}:latest-${ARCH_NAME}
                                    fi
                                    
                                    SIZE=\$(docker inspect ${BASENAME}:${DIST_NAME}-${ARCH_NAME} --format='{{.Size}}' | awk '{printf "%.1fMB", \$1/1024/1024}')
                                    echo "Image: ${BASENAME}:${DIST_NAME}-${ARCH_NAME} (\${SIZE})"
                                """
                            }
                        }
                    }
                    
                    stage('Test') {
                        steps {
                            container('docker') {
                                sh """
                                    echo "Testing ${DIST_NAME}-${ARCH_NAME}"
                                    
                                    docker run --rm ${BASENAME}:${DIST_NAME}-${ARCH_NAME} \
                                        bash -c 'cat /etc/os-release | head -2'
                                    
                                    docker run --rm ${BASENAME}:${DIST_NAME}-${ARCH_NAME} \
                                        bash -c 'install_packages curl && curl --version | head -1'
                                    
                                    echo "Tests passed"
                                """
                            }
                        }
                    }
                    
                    stage('Security') {
                        when {
                            expression { params.RUN_SECURITY_SCAN }
                        }
                        steps {
                            container('trivy') {
                                sh """
                                    trivy image \
                                        --severity HIGH,CRITICAL \
                                        --exit-code 0 \
                                        ${BASENAME}:${DIST_NAME}-${ARCH_NAME}
                                    
                                    trivy image \
                                        --severity HIGH,CRITICAL \
                                        --format json \
                                        --output build/trivy-${DIST_NAME}-${ARCH_NAME}.json \
                                        ${BASENAME}:${DIST_NAME}-${ARCH_NAME} || true
                                """
                            }
                        }
                    }
                    
                    stage('Push') {
                        when {
                            expression { params.PUSH_TO_REGISTRY }
                        }
                        steps {
                            container('docker') {
                                sh """
                                    echo "Pushing ${DIST_NAME}-${ARCH_NAME}"
                                    
                                    echo \${DOCKERHUB_PSW} | docker login -u \${DOCKERHUB_USR} --password-stdin
                                    
                                    docker push ${BASENAME}:${DIST_NAME}-${ARCH_NAME}
                                    docker push ${BASENAME}:${DIST_NAME}-${ARCH_NAME}-${BUILD_DATE}
                                    
                                    if [ "${DIST_NAME}" == "${LATEST}" ]; then
                                        docker push ${BASENAME}:latest-${ARCH_NAME}
                                    fi
                                    
                                    docker logout
                                """
                            }
                        }
                    }
                }
            }
        }
        
        stage('Manifests') {
            when {
                allOf {
                    expression { params.PUSH_TO_REGISTRY }
                    expression { params.CREATE_MANIFESTS }
                    expression { params.ARCH == 'all' }
                }
            }
            steps {
                container('docker') {
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
                        
                        if (dists.contains(env.LATEST)) {
                            sh """
                                docker manifest create ${BASENAME}:latest \
                                    --amend ${BASENAME}:latest-amd64 \
                                    --amend ${BASENAME}:latest-arm64
                                
                                docker manifest push ${BASENAME}:latest
                            """
                        }
                        
                        sh "docker logout"
                    }
                }
            }
        }
        
        stage('Report') {
            steps {
                container('docker') {
                    sh '''
                        cat > build-report.md << EOF
# VCNNGR MinidEB Build Report

**Build:** ${BUILD_NUMBER}
**Date:** ${BUILD_TIMESTAMP}
**Commit:** ${GIT_COMMIT_SHORT}

## Images Built

EOF
                        docker images ${BASENAME} --format "- {{.Repository}}:{{.Tag}} ({{.Size}})" >> build-report.md
                        
                        echo "" >> build-report.md
                        echo "## Security Scans" >> build-report.md
                        for report in build/trivy-*.json; do
                            [ -f "$report" ] && echo "- $(basename $report)" >> build-report.md
                        done || true
                        
                        cat build-report.md
                    '''
                }
            }
        }
    }
    
    post {
        always {
            archiveArtifacts artifacts: 'build-report.md,build/*.log,build/trivy-*.json', 
                             allowEmptyArchive: true
            container('docker') {
                sh 'docker system prune -f || true'
            }
        }
        
        success {
            echo """
╔════════════════════════════════════════════╗
║   BUILD SUCCESSFUL                         ║
╚════════════════════════════════════════════╝

Images: https://hub.docker.com/r/vcnngr/minideb
"""
        }
        
        failure {
            echo "Build failed - check console output"
        }
    }
}
