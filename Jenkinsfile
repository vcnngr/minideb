pipeline {
    agent {
        kubernetes {
            yaml """
apiVersion: v1
kind: Pod
metadata:
  labels:
    jenkins: agent
    job: vcnngr-minideb-buildah
spec:
  serviceAccountName: jenkins-agent
  securityContext:
    runAsUser: 0
    fsGroup: 0
  containers:
  - name: builder
    image: quay.io/buildah/stable:v1.33
    command: [cat]
    tty: true
    securityContext:
      privileged: true
    env:
    - name: STORAGE_DRIVER
      value: "vfs"
    - name: BUILDAH_FORMAT
      value: "docker"
    resources:
      requests:
        memory: "4Gi"
        cpu: "2000m"
      limits:
        memory: "8Gi"
        cpu: "4000m"
  
  - name: sonar-scanner
    image: sonarsource/sonar-scanner-cli:latest
    command: [cat]
    tty: true
  - name: trivy
    image: aquasec/trivy:latest
    command: [cat]
    tty: true
"""
        }
    }
    
    environment {
        BASENAME = 'vcnngr/minideb'
        DOCKER_REGISTRY = 'docker.io'
        LATEST = 'trixie'
        
        DOCKERHUB = credentials('dockerhub-credentials')
        SONAR_TOKEN = credentials('sonarqube-token')
        
        GIT_COMMIT_SHORT = sh(returnStdout: true, script: 'git rev-parse --short HEAD').trim()
        BUILD_DATE = sh(returnStdout: true, script: 'date -u +%Y%m%d').trim()
        // FORMATO CRUCIALE: ISO 8601/RFC3339 (es. 2023-10-25T14:30:00Z)
        // Questo formato è identico a quello che generava il tuo vecchio script bash.
        BUILD_TIMESTAMP = sh(returnStdout: true, script: 'date -u +%Y-%m-%dT%H:%M:%SZ').trim()
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
                    echo "--- VCNNGR Minideb Build (Buildah Edition) ---"
                    def dists = params.DIST == 'all' ? ['bullseye', 'bookworm', 'trixie'] : [params.DIST]
                    def archs = params.ARCH == 'all' ? ['amd64', 'arm64'] : [params.ARCH]
                    
                    env.BUILD_DISTS = dists.join(',')
                    env.BUILD_ARCHS = archs.join(',')
                }
            }
        }
        
        stage('Setup') {
            steps {
                container('builder') {
                    // Installazione dipendenze:
                    // - debootstrap: per mkimage
                    // - podman: per i test (podman run)
                    // - jq/git: utility
                    sh '''
                        echo "Installing dependencies..."
                        dnf install -y debootstrap jq debian-keyring qemu-user-static podman git > /dev/null
                        
                        echo "Check tools:"
                        buildah --version
                        podman --version
                        
                        chmod +x mkimage import-buildah
                    '''
                }
            }
        }
        
        stage('Code Quality') {
             parallel {
                stage('Shellcheck') {
                    steps {
                        container('builder') {
                             sh 'echo "Skipping shellcheck check in builder" || true'
                        }
                    }
                }
                stage('SonarQube') {
                    when { expression { params.RUN_SONARQUBE } }
                    steps {
                        container('sonar-scanner') {
                            script {
                                try {
                                    sh """
                                        sonar-scanner \
                                            -Dsonar.host.url=http://sonarqube-sonarqube.jenkins.svc.cluster.local:9000 \
                                            -Dsonar.token=${SONAR_TOKEN} \
                                            -Dsonar.projectKey=vcnngr-minideb \
                                            -Dsonar.projectName='VCNNGR Minideb' \
                                            -Dsonar.projectVersion=${BUILD_DATE}-${GIT_COMMIT_SHORT} \
                                            -Dsonar.sources=. \
                                            -Dsonar.scm.disabled=true
                                    """
                                } catch (Exception e) {
                                    echo "SonarQube skipped/failed: ${e.message}"
                                }
                            }
                        }
                    }
                }
             }
        }

        stage('Build Images') {
            matrix {
                axes {
                    axis { name 'DIST_NAME'; values 'bullseye', 'bookworm', 'trixie' }
                    axis { name 'ARCH_NAME'; values 'amd64', 'arm64' }
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
                            container('builder') {
                                sh """
                                    echo "Building Base RootFS for ${DIST_NAME}-${ARCH_NAME}"
                                    mkdir -p build
                                    
                                    # Generazione rootfs con debootstrap
                                    ./mkimage "build/${DIST_NAME}-${ARCH_NAME}.tar" "${DIST_NAME}" "${ARCH_NAME}"
                                """
                            }
                        }
                    }
                    
                    stage('Import & Tag') {
                        steps {
                            container('builder') {
                                sh """
                                    # Import con Buildah usando il timestamp per riproducibilità
                                    ./import-buildah "build/${DIST_NAME}-${ARCH_NAME}.tar" "${BUILD_TIMESTAMP}" "${ARCH_NAME}" > image_id.txt
                                    
                                    IMAGE_ID=\$(cat image_id.txt)
                                    echo "Created Image ID: \$IMAGE_ID"
                                    
                                    # Tagging locale
                                    buildah tag \$IMAGE_ID ${BASENAME}:${DIST_NAME}-${ARCH_NAME}
                                    buildah tag \$IMAGE_ID ${BASENAME}:${DIST_NAME}-${ARCH_NAME}-${BUILD_DATE}
                                    buildah tag \$IMAGE_ID ${BASENAME}:${DIST_NAME}-${ARCH_NAME}-${BUILD_TIMESTAMP}
                                    
                                    if [ "${DIST_NAME}" = "${LATEST}" ]; then
                                        buildah tag \$IMAGE_ID ${BASENAME}:latest-${ARCH_NAME}
                                    fi
                                    
                                    buildah images
                                """
                            }
                        }
                    }
                    
                    stage('Test') {
                        steps {
                            container('builder') {
                                sh """
                                    echo "Testing ${DIST_NAME}-${ARCH_NAME}"
                                    
                                    # Podman run sostituisce docker run
                                    podman run --rm ${BASENAME}:${DIST_NAME}-${ARCH_NAME} cat /etc/os-release | head -2
                                    podman run --rm ${BASENAME}:${DIST_NAME}-${ARCH_NAME} dpkg --print-architecture
                                """
                            }
                        }
                    }
                    
                    stage('Security') {
                        when { expression { params.RUN_SECURITY_SCAN } }
                        steps {
                            container('trivy') {
                                sh """
                                    mkdir -p build/security
                                    trivy image \
                                        --input "build/${DIST_NAME}-${ARCH_NAME}.tar" \
                                        --severity HIGH,CRITICAL \
                                        --format json \
                                        --output build/security/trivy-${DIST_NAME}-${ARCH_NAME}.json || true
                                """
                            }
                        }
                    }
                    
                    stage('Push') {
                        when { expression { params.PUSH_TO_REGISTRY } }
                        steps {
                            container('builder') {
                                sh """
                                    echo "Pushing..."
                                    echo \${DOCKERHUB_PSW} | buildah login -u \${DOCKERHUB_USR} --password-stdin ${DOCKER_REGISTRY}
                                    
                                    buildah push ${BASENAME}:${DIST_NAME}-${ARCH_NAME}
                                    buildah push ${BASENAME}:${DIST_NAME}-${ARCH_NAME}-${BUILD_DATE}
                                    buildah push ${BASENAME}:${DIST_NAME}-${ARCH_NAME}-${BUILD_TIMESTAMP}
                                    
                                    if [ "${DIST_NAME}" = "${LATEST}" ]; then
                                        buildah push ${BASENAME}:latest-${ARCH_NAME}
                                    fi
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
                container('builder') {
                    script {
                        def dists = env.BUILD_DISTS.split(',')
                        
                        sh "echo \${DOCKERHUB_PSW} | buildah login -u \${DOCKERHUB_USR} --password-stdin ${DOCKER_REGISTRY}"
                        
                        dists.each { dist ->
                            sh """
                                echo "Manifest per ${dist}..."
                                buildah manifest rm ${BASENAME}:${dist} || true
                                buildah manifest create ${BASENAME}:${dist}
                                
                                buildah manifest add ${BASENAME}:${dist} docker://${BASENAME}:${dist}-amd64
                                buildah manifest add ${BASENAME}:${dist} docker://${BASENAME}:${dist}-arm64
                                
                                buildah manifest push --all ${BASENAME}:${dist} docker://${BASENAME}:${dist}
                            """
                        }
                        
                        if (dists.contains(env.LATEST)) {
                            sh """
                                echo "Manifest per latest..."
                                buildah manifest rm ${BASENAME}:latest || true
                                buildah manifest create ${BASENAME}:latest
                                buildah manifest add ${BASENAME}:latest docker://${BASENAME}:latest-amd64
                                buildah manifest add ${BASENAME}:latest docker://${BASENAME}:latest-arm64
                                buildah manifest push --all ${BASENAME}:latest docker://${BASENAME}:latest
                            """
                        }
                    }
                }
            }
        }
        
        stage('Generate Report') {
             steps {
                container('builder') {
                    sh '''
                        echo "# VCNNGR Minideb Report" > build-report.md
                        buildah images >> build-report.md
                    '''
                }
             }
        }
    }
    
    post {
        always {
            archiveArtifacts artifacts: 'build-report.md,build/**/*.log,build/security/*.json', allowEmptyArchive: true
            container('builder') {
                sh 'buildah rm --all || true'
                sh 'buildah rmi --prune || true'
            }
        }
    }
}
