// VCNNGR MinidEB Pipeline - Production Ready
// Optimized for actual import script behavior

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
        BUILD_TIMESTAMP = sh(returnStdout: true, script: 'date -u +%Y-%m-%dT%H:%M:%SZ').trim()
    }
    
    parameters {
        choice(name: 'DIST', choices: ['all', 'bullseye', 'bookworm', 'trixie'], description: 'Distribution')
        choice(name: 'ARCH', choices: ['all', 'amd64', 'arm64'], description: 'Architecture')
        booleanParam(name: 'PUSH_TO_REGISTRY', defaultValue: false, description: 'Push to Docker Hub')
        booleanParam(name: 'CREATE_MANIFESTS', defaultValue: true, description: 'Create manifests')
        booleanParam(name: 'RUN_SECURITY_SCAN', defaultValue: true, description: 'Run security scan')
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
                        set -e
                        apt-get update -qq
                        apt-get install -y -qq \
                            debootstrap debian-archive-keyring jq dpkg-dev \
                            gnupg curl shellcheck git rsync qemu-user-static \
                            docker.io
                        
                        # Ensure scripts are executable
                        chmod +x mkimage import buildone test pushone pushall pushmanifest || true
                        
                        # Setup QEMU for cross-platform builds
                        docker run --rm --privileged multiarch/qemu-user-static --reset -p yes || true
                    '''
                }
            }
        }
        
        stage('Code Quality') {
            steps {
                container('debian') {
                    sh '''
                        if [ -f shellcheck ]; then
                            bash shellcheck || echo "Shellcheck warnings found"
                        else
                            shellcheck mkimage import buildone || echo "Shellcheck completed with warnings"
                        fi
                    '''
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
                                    
                                    if [ ! -f "build/${DIST_NAME}-${ARCH_NAME}.tar" ]; then
                                        echo "ERROR: Tarball not created"
                                        exit 1
                                    fi
                                    
                                    ls -lh build/${DIST_NAME}-${ARCH_NAME}.tar
                                """
                            }
                        }
                    }
                    
                    stage('Import & Tag') {
                        steps {
                            container('debian') {
                                sh """
                                    set -e
                                    
                                    echo "Importing ${DIST_NAME}-${ARCH_NAME}"
                                    cd ${WORKSPACE}
                                    
                                    # Generate timestamp in ISO 8601 format
                                    TIMESTAMP=\$(date -u +%Y-%m-%dT%H:%M:%SZ)
                                    echo "Using timestamp: \${TIMESTAMP}"
                                    
                                    # Check if image exists and use its timestamp
                                    if docker pull ${BASENAME}:${DIST_NAME}-${ARCH_NAME} 2>/dev/null; then
                                        EXISTING_TS=\$(docker inspect ${BASENAME}:${DIST_NAME}-${ARCH_NAME} --format='{{.Created}}' 2>/dev/null || echo "")
                                        if [ -n "\${EXISTING_TS}" ]; then
                                            TIMESTAMP="\${EXISTING_TS}"
                                            echo "Using existing image timestamp: \${TIMESTAMP}"
                                        fi
                                    fi
                                    
                                    # Execute import script (it's a bash script)
                                    echo "Running import script..."
                                    IMAGE_ID=\$(bash ./import "build/${DIST_NAME}-${ARCH_NAME}.tar" "\${TIMESTAMP}" "${ARCH_NAME}")
                                    
                                    if [ -z "\${IMAGE_ID}" ]; then
                                        echo "ERROR: Failed to import image - IMAGE_ID is empty"
                                        exit 1
                                    fi
                                    
                                    echo "Successfully imported image: \${IMAGE_ID}"
                                    
                                    # Tag images
                                    docker tag \${IMAGE_ID} ${BASENAME}:${DIST_NAME}-${ARCH_NAME}
                                    docker tag \${IMAGE_ID} ${BASENAME}:${DIST_NAME}-${ARCH_NAME}-${BUILD_DATE}
                                    docker tag \${IMAGE_ID} ${BASENAME}:${DIST_NAME}-${ARCH_NAME}-${BUILD_TIMESTAMP}
                                    
                                    if [ "${DIST_NAME}" = "${LATEST}" ]; then
                                        docker tag \${IMAGE_ID} ${BASENAME}:latest-${ARCH_NAME}
                                    fi
                                    
                                    # Show image info
                                    SIZE=\$(docker inspect \${IMAGE_ID} --format='{{.Size}}' | awk '{printf "%.1fMB", \$1/1024/1024}')
                                    echo "Image: ${BASENAME}:${DIST_NAME}-${ARCH_NAME} (\${SIZE})"
                                    
                                    docker images ${BASENAME}:${DIST_NAME}-${ARCH_NAME}
                                """
                            }
                        }
                    }
                    
                    stage('Test') {
                        steps {
                            container('debian') {
                                sh """
                                    echo "Testing ${DIST_NAME}-${ARCH_NAME}"
                                    
                                    # Test 1: Check OS release
                                    echo "Test 1: OS Release"
                                    docker run --rm ${BASENAME}:${DIST_NAME}-${ARCH_NAME} \
                                        bash -c 'cat /etc/os-release | head -2'
                                    
                                    # Test 2: Test install_packages
                                    echo "Test 2: Package Installation"
                                    docker run --rm ${BASENAME}:${DIST_NAME}-${ARCH_NAME} \
                                        bash -c 'apt-get update -qq && apt-get install -y -qq curl && curl --version | head -1'
                                    
                                    # Test 3: Check architecture
                                    echo "Test 3: Architecture"
                                    docker run --rm ${BASENAME}:${DIST_NAME}-${ARCH_NAME} \
                                        bash -c 'dpkg --print-architecture'
                                    
                                    echo "All tests passed for ${DIST_NAME}-${ARCH_NAME}"
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
                                    mkdir -p build/security
                                    
                                    echo "Running security scan for ${DIST_NAME}-${ARCH_NAME}"
                                    
                                    trivy image \
                                        --severity HIGH,CRITICAL \
                                        --exit-code 0 \
                                        --timeout 10m \
                                        ${BASENAME}:${DIST_NAME}-${ARCH_NAME}
                                    
                                    trivy image \
                                        --format json \
                                        --output build/security/trivy-${DIST_NAME}-${ARCH_NAME}.json \
                                        ${BASENAME}:${DIST_NAME}-${ARCH_NAME} || true
                                    
                                    echo "Security scan completed"
                                """
                            }
                        }
                    }
                    
                    stage('Push') {
                        when {
                            expression { params.PUSH_TO_REGISTRY }
                        }
                        steps {
                            container('debian') {
                                sh """
                                    echo "Pushing ${DIST_NAME}-${ARCH_NAME} to registry"
                                    
                                    echo \${DOCKERHUB_PSW} | docker login -u \${DOCKERHUB_USR} --password-stdin
                                    
                                    docker push ${BASENAME}:${DIST_NAME}-${ARCH_NAME}
                                    docker push ${BASENAME}:${DIST_NAME}-${ARCH_NAME}-${BUILD_DATE}
                                    
                                    if [ "${DIST_NAME}" = "${LATEST}" ]; then
                                        docker push ${BASENAME}:latest-${ARCH_NAME}
                                    fi
                                    
                                    docker logout
                                    echo "Push completed"
                                """
                            }
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
                container('debian') {
                    script {
                        def dists = env.BUILD_DISTS.split(',')
                        
                        sh "echo \${DOCKERHUB_PSW} | docker login -u \${DOCKERHUB_USR} --password-stdin"
                        
                        dists.each { dist ->
                            sh """
                                echo "Creating manifest for ${dist}"
                                
                                docker manifest create ${BASENAME}:${dist} \
                                    --amend ${BASENAME}:${dist}-amd64 \
                                    --amend ${BASENAME}:${dist}-arm64
                                
                                docker manifest push ${BASENAME}:${dist}
                                
                                echo "Manifest ${BASENAME}:${dist} created and pushed"
                            """
                        }
                        
                        if (dists.contains(env.LATEST)) {
                            sh """
                                echo "Creating latest manifest"
                                
                                docker manifest create ${BASENAME}:latest \
                                    --amend ${BASENAME}:latest-amd64 \
                                    --amend ${BASENAME}:latest-arm64
                                
                                docker manifest push ${BASENAME}:latest
                                
                                echo "Latest manifest created"
                            """
                        }
                        
                        sh "docker logout"
                    }
                }
            }
        }
        
        stage('Generate Report') {
            steps {
                container('debian') {
                    sh '''
                        cat > build-report.md << 'EOFMARKER'
# VCNNGR MinidEB Build Report

**Build Number:** ${BUILD_NUMBER}
**Build Date:** ${BUILD_TIMESTAMP}
**Git Commit:** ${GIT_COMMIT_SHORT}
**Distribution:** ${DIST}
**Architecture:** ${ARCH}

## Images Built

EOFMARKER
                        
                        docker images ${BASENAME} --format "- {{.Repository}}:{{.Tag}} ({{.Size}})" >> build-report.md || echo "No images found" >> build-report.md
                        
                        echo "" >> build-report.md
                        echo "## Security Scans" >> build-report.md
                        
                        if ls build/security/trivy-*.json 1> /dev/null 2>&1; then
                            for report in build/security/trivy-*.json; do
                                echo "- $(basename $report)" >> build-report.md
                            done
                        else
                            echo "No security reports generated" >> build-report.md
                        fi
                        
                        cat build-report.md
                    '''
                }
            }
        }
    }
    
    post {
        always {
            archiveArtifacts artifacts: 'build-report.md,build/**/*.log,build/security/*.json', 
                             allowEmptyArchive: true
            container('debian') {
                sh 'docker system prune -af --volumes || true'
            }
        }
        
        success {
            echo """
╔════════════════════════════════════════════╗
║   BUILD SUCCESSFUL                         ║
╚════════════════════════════════════════════╝

Images available at: https://hub.docker.com/r/vcnngr/minideb
Build artifacts archived in Jenkins
"""
        }
        
        failure {
            echo """
╔════════════════════════════════════════════╗
║   BUILD FAILED                             ║
╚════════════════════════════════════════════╝

Check console output for errors
Review archived artifacts for details
"""
        }
    }
}
