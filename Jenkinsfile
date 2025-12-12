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
  
  # InitContainer: Registra QEMU nel Kernel dell'host (Fix per ARM64)
  initContainers:
  - name: register-qemu
    image: multiarch/qemu-user-static
    args: ["--reset", "-p", "yes"]
    securityContext:
      privileged: true

  containers:
  - name: builder
    image: debian:bookworm
    command: [cat]
    tty: true
    securityContext:
      privileged: true
    env:
    - name: STORAGE_DRIVER
      value: "vfs"
    - name: BUILDAH_FORMAT
      value: "docker"
    # Risorse aumentate per gestire l'emulazione QEMU senza stalli
    resources:
      requests:
        memory: "4Gi"
        cpu: "2000m"
      limits:
        memory: "8Gi"
        cpu: "6000m"
  
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
        
        // Credenziali caricate come variabili d'ambiente
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
                    echo "--- VCNNGR Minideb Build (Secure & Sequential) ---"
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
                    // Installazione tool su Debian Bookworm
                    sh '''
                        apt-get update -qq
                        apt-get install -y -qq \
                            buildah \
                            podman \
                            qemu-user-static \
                            debootstrap \
                            jq \
                            curl \
                            git \
                            dpkg-dev \
                            perl \
                            debian-archive-keyring
                        
                        echo "Check tools:"
                        buildah --version
                        podman --version
                        
                        if [ ! -f /proc/sys/fs/binfmt_misc/qemu-aarch64 ]; then
                            echo "WARNING: QEMU not found in /proc. ARM builds might fail!"
                        else
                            echo "QEMU aarch64 is active."
                        fi
                        
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
                             sh 'echo "Skipping shellcheck" || true'
                        }
                    }
                }
                stage('SonarQube') {
                    when { expression { params.RUN_SONARQUBE } }
                    steps {
                        container('sonar-scanner') {
                            script {
                                try {
                                    // SECURITY FIX: Usiamo \$SONAR_TOKEN invece di ${SONAR_TOKEN}
                                    // Così è la shell a leggere la variabile, non Groovy a interpolarla.
                                    sh """
                                        sonar-scanner \
                                            -Dsonar.host.url=http://sonarqube-sonarqube.jenkins.svc.cluster.local:9000 \
                                            -Dsonar.token=\$SONAR_TOKEN \
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
                    stage('Build Sequence') {
                        // CONCURRENCY FIX: Il lock forza l'esecuzione sequenziale.
                        // Evita che 6 istanze di QEMU soffochino la CPU del nodo.
                        options {
                            lock(resource: 'vcnngr-build-cpu', inversePrecedence: true) 
                        }
                        stages {
                            stage('Create Base') {
                                steps {
                                    container('builder') {
                                        sh """
                                            echo "Building Base RootFS for ${DIST_NAME}-${ARCH_NAME}"
                                            mkdir -p build
                                            ./mkimage "build/${DIST_NAME}-${ARCH_NAME}.tar" "${DIST_NAME}" "${ARCH_NAME}"
                                        """
                                    }
                                }
                            }
                            
                            stage('Import & Tag') {
                                steps {
                                    container('builder') {
                                        sh """
                                            ./import-buildah "build/${DIST_NAME}-${ARCH_NAME}.tar" "${BUILD_TIMESTAMP}" "${ARCH_NAME}" > image_id.txt
                                            
                                            IMAGE_ID=\$(cat image_id.txt)
                                            echo "Created Image ID: \$IMAGE_ID"
                                            
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
                                        // SECURITY FIX: Usiamo \$ per le variabili sensibili
                                        sh """
                                            echo "Pushing..."
                                            echo \$DOCKERHUB_PSW | buildah login -u \$DOCKERHUB_USR --password-stdin ${DOCKER_REGISTRY}
                                            
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
                        
                        // SECURITY FIX: Escape delle credenziali
                        sh "echo \$DOCKERHUB_PSW | buildah login -u \$DOCKERHUB_USR --password-stdin ${DOCKER_REGISTRY}"
                        
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
