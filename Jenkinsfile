// VCNNGR MinidEB Pipeline - Production Ready
// Kubernetes Native - Jenkins 2.530+

pipeline {
    agent {
        kubernetes {
            yaml '''
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
'''
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
        choice(
            name: 'DIST', 
            choices: ['all', 'bullseye', 'bookworm', 'trixie'], 
            description: 'Debian distribution'
        )
        choice(
            name: 'ARCH', 
            choices: ['all', 'amd64', 'arm64'], 
            description: 'Target architecture'
        )
        booleanParam(
            name: 'PUSH_TO_REGISTRY', 
            defaultValue: true, 
            description: 'Push images to Docker Hub'
        )
        booleanParam(
            name: 'CREATE_MANIFESTS', 
            defaultValue: true, 
            description: 'Create multi-arch manifests'
        )
        booleanParam(
            name: 'RUN_SECURITY_SCAN', 
            defaultValue: true, 
            description: 'Run Trivy security scan'
        )
    }
    
    options {
        buildDiscarder(logRotator(numToKeepStr: '30', artifactNumToKeepStr: '10'))
        timestamps()
        timeout(time: 6, unit: 'HOURS')
        disableConcurrentBuilds()
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
Git Commit:   ${GIT_COMMIT_SHORT}
Pod:          ${env.NODE_NAME}
Namespace:    jenkins
"""
                    
                    def dists = params.DIST == 'all' ? ['bullseye', 'bookworm', 'trixie'] : [params.DIST]
                    def archs = params.ARCH == 'all' ? ['amd64', 'arm64'] : [params.ARCH]
                    
                    env.BUILD_DISTS = dists.join(',')
                    env.BUILD_ARCHS = archs.join(',')
                    env.BUILD_COMBINATIONS = "${dists.size() * archs.size()}"
                    
                    echo "Building: ${env.BUILD_DISTS} × ${env.BUILD_ARCHS} (${env.BUILD_COMBINATIONS} combinations)"
                }
            }
        }
        
        stage('Setup Environment') {
            steps {
                container('debian') {
                    sh '''
                        echo "Installing build dependencies..."
                        apt-get update -qq
                        apt-get install -y -qq \
                            debootstrap \
                            debian-archive-keyring \
                            jq \
                            dpkg-dev \
                            gnupg \
                            apt-transport-https \
                            ca-certificates \
                            curl \
                            shellcheck \
                            git \
                            rsync \
                            qemu-user-static \
                            binfmt-support \
                            > /dev/null 2>&1
                        
                        echo "Dependencies installed"
                        debootstrap --version | head -1
                        shellcheck --version | head -1
                    '''
                }
                
                container('docker') {
                    sh '''
                        echo "Setting up multi-arch support..."
                        docker run --rm --privileged multiarch/qemu-user-static --reset -p yes || true
                        docker buildx create --use --name vcnngr-builder || docker buildx use vcnngr-builder
                        docker buildx inspect --bootstrap
                        echo "Multi-arch ready"
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
                        expression { 
                            // SonarQube opzionale - non blocca se non configurato
                            try {
                                return env.SONARQUBE_SERVER != null
                            } catch (Exception e) {
                                return false
                            }
                        }
                    }
                    steps {
                        container('debian') {
                            script {
                                try {
                                    withSonarQubeEnv('SonarQube-Server') {
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
                                    echo "WARNING: SonarQube analysis failed: ${e.message}"
                                    echo "Continuing build without SonarQube"
                                }
                            }
                        }
                    }
                }
            }
        }
        
        stage('Quality Gate') {
            when {
                expression { 
                    // Quality Gate solo se SonarQube è configurato
                    try {
                        return env.SONARQUBE_SERVER != null
                    } catch (Exception e) {
                        return false
                    }
                }
            }
            steps {
                timeout(time: 10, unit: 'MINUTES') {
                    script {
                        try {
                            def qg = waitForQualityGate()
                            if (qg.status != 'OK') {
                                echo "WARNING: Quality Gate ${qg.status}"
                            }
                        } catch (Exception e) {
                            echo "WARNING: Quality Gate check failed: ${e.message}"
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
                        def dists = env.BUILD_DISTS.split(',')
                        def archs = env.BUILD_ARCHS.split(',')
                        return dists.contains(DIST_NAME) && archs.contains(ARCH_NAME)
                    }
                }
                
                stages {
                    stage('Build') {
                        steps {
                            container('debian') {
                                script {
                                    echo "Building ${DIST_NAME}-${ARCH_NAME}"
                                    
                                    sh """
                                        mkdir -p build
                                        
                                        # Execute Bitnami build system
                                        ./buildone ${DIST_NAME} ${ARCH_NAME}
                                        
                                        # Retag as vcnngr
                                        docker tag bitnami/minideb:${DIST_NAME}-${ARCH_NAME} \
                                                   ${BASENAME}:${DIST_NAME}-${ARCH_NAME}
                                        
                                        # Tag with date
                                        docker tag ${BASENAME}:${DIST_NAME}-${ARCH_NAME} \
                                                   ${BASENAME}:${DIST_NAME}-${ARCH_NAME}-${BUILD_DATE}
                                        
                                        # Tag latest if applicable
                                        if [ "${DIST_NAME}" == "${LATEST}" ]; then
                                            docker tag ${BASENAME}:${DIST_NAME}-${ARCH_NAME} \
                                                       ${BASENAME}:latest-${ARCH_NAME}
                                        fi
                                        
                                        # Show result
                                        docker images ${BASENAME}:${DIST_NAME}-${ARCH_NAME}
                                        SIZE=\$(docker inspect ${BASENAME}:${DIST_NAME}-${ARCH_NAME} --format='{{.Size}}' | \
                                               awk '{printf "%.1fMB", \$1/1024/1024}')
                                        echo "Image size: \${SIZE}"
                                    """
                                }
                            }
                        }
                    }
                    
                    stage('Test') {
                        steps {
                            container('debian') {
                                sh """
                                    echo "Testing ${DIST_NAME}-${ARCH_NAME}..."
                                    
                                    # Basic tests
                                    docker run --rm ${BASENAME}:${DIST_NAME}-${ARCH_NAME} \
                                        bash -c 'cat /etc/os-release'
                                    
                                    # Test install_packages
                                    docker run --rm ${BASENAME}:${DIST_NAME}-${ARCH_NAME} \
                                        bash -c 'install_packages curl && curl --version'
                                    
                                    echo "Tests passed"
                                """
                            }
                        }
                    }
                    
                    stage('Security Scan') {
                        when {
                            expression { params.RUN_SECURITY_SCAN }
                        }
                        steps {
                            container('trivy') {
                                sh """
                                    trivy image \
                                        --severity HIGH,CRITICAL \
                                        --exit-code 0 \
                                        --format table \
                                        --timeout 15m \
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
                                    echo "Pushing ${DIST_NAME}-${ARCH_NAME}..."
                                    
                                    echo \${DOCKERHUB_PSW} | docker login -u \${DOCKERHUB_USR} --password-stdin
                                    
                                    docker push ${BASENAME}:${DIST_NAME}-${ARCH_NAME}
                                    docker push ${BASENAME}:${DIST_NAME}-${ARCH_NAME}-${BUILD_DATE}
                                    
                                    if [ "${DIST_NAME}" == "${LATEST}" ]; then
                                        docker push ${BASENAME}:latest-${ARCH_NAME}
                                    fi
                                    
                                    docker logout
                                    echo "Push complete"
                                """
                            }
                        }
                    }
                }
            }
        }
        
        stage('Multi-Arch Manifests') {
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
                        echo "Creating multi-architecture manifests"
                        
                        def dists = env.BUILD_DISTS.split(',')
                        
                        sh "echo \${DOCKERHUB_PSW} | docker login -u \${DOCKERHUB_USR} --password-stdin"
                        
                        dists.each { dist ->
                            sh """
                                echo "Manifest for ${dist}..."
                                
                                docker manifest create ${BASENAME}:${dist} \
                                    --amend ${BASENAME}:${dist}-amd64 \
                                    --amend ${BASENAME}:${dist}-arm64
                                
                                docker manifest annotate ${BASENAME}:${dist} \
                                    ${BASENAME}:${dist}-amd64 --arch amd64
                                docker manifest annotate ${BASENAME}:${dist} \
                                    ${BASENAME}:${dist}-arm64 --arch arm64
                                
                                docker manifest push ${BASENAME}:${dist}
                                echo "Manifest ${dist} created"
                            """
                        }
                        
                        if (dists.contains(env.LATEST)) {
                            sh """
                                echo "Manifest for latest..."
                                
                                docker manifest create ${BASENAME}:latest \
                                    --amend ${BASENAME}:latest-amd64 \
                                    --amend ${BASENAME}:latest-arm64
                                
                                docker manifest annotate ${BASENAME}:latest \
                                    ${BASENAME}:latest-amd64 --arch amd64
                                docker manifest annotate ${BASENAME}:latest \
                                    ${BASENAME}:latest-arm64 --arch arm64
                                
                                docker manifest push ${BASENAME}:latest
                                echo "Latest manifest created"
                            """
                        }
                        
                        sh "docker logout"
                    }
                }
            }
        }
        
        stage('Generate Reports') {
            steps {
                container('debian') {
                    sh '''
                        cat > build-report.md << EOF
# VCNNGR MinidEB Build Report

**Build:** ${BUILD_NUMBER}
**Date:** ${BUILD_TIMESTAMP}
**Commit:** ${GIT_COMMIT_SHORT}
**Dists:** ${BUILD_DISTS}
**Archs:** ${BUILD_ARCHS}

## Images

EOF
                        docker images ${BASENAME} --format "table {{.Repository}}:{{.Tag}}\t{{.Size}}\t{{.CreatedSince}}" >> build-report.md
                        
                        echo "" >> build-report.md
                        echo "## Security Scans" >> build-report.md
                        for report in build/trivy-*.json; do
                            [ -f "$report" ] && echo "- $(basename $report)" >> build-report.md
                        done || true
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
            script {
                echo """
╔════════════════════════════════════════════╗
║   BUILD SUCCESSFUL                         ║
╚════════════════════════════════════════════╝

Images: https://hub.docker.com/r/vcnngr/minideb

Pull:
  docker pull ${BASENAME}:bookworm
  docker pull ${BASENAME}:latest
"""
                
                if (params.PUSH_TO_REGISTRY) {
                    try {
                        build job: 'vcnngr-containers-update', 
                            parameters: [
                                string(name: 'BASE_IMAGE', value: 'minideb'),
                                string(name: 'BUILD_DATE', value: "${BUILD_DATE}")
                            ],
                            wait: false,
                            propagate: false
                    } catch (Exception e) {
                        echo "Containers job not configured yet"
                    }
                }
            }
        }
        
        failure {
            echo "BUILD FAILED - Check console output"
        }
    }
}
