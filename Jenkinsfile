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
  # 1. Questo è il nuovo container che sostituisce 'debian'. 
  # Ha già Buildah e Podman installati.
  - name: builder
    image: quay.io/buildah/stable:v1.33
    command: [cat]
    tty: true
    securityContext:
      privileged: true
    env:
    # 2. Configurazione automatica per evitare errori di storage su Kubernetes
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
  
  # Container ausiliari (uguali a prima)
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
                    // Qui installiamo debootstrap e jq perché l'immagine 'buildah' di base non li ha.
                    // Così non devi creare tu un'immagine docker custom.
                    sh '''
                        echo "Installing dependencies..."
                        dnf install -y debootstrap jq debian-keyring qemu-user-static > /dev/null
                        
                        echo "Check tools:"
                        buildah --version
                        podman --version
                        
                        chmod +x mkimage import-buildah
                    '''
                }
            }
        }
        
        // ... (Stage Code Quality / Sonar rimangono identici a prima, saltati per brevità ma puoi lasciarli) ...

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
                                    
                                    # Usa il tuo script mkimage esistente (che usa debootstrap)
                                    ./mkimage "build/${DIST_NAME}-${ARCH_NAME}.tar" "${DIST_NAME}" "${ARCH_NAME}"
                                """
                            }
                        }
                    }
                    
                    stage('Import & Tag') {
                        steps {
                            container('builder') {
                                sh """
                                    # Usa il NUOVO script import-buildah
                                    # Questo crea l'immagine usando Buildah invece di Docker Daemon
                                    ./import-buildah "build/${DIST_NAME}-${ARCH_NAME}.tar" "${BUILD_TIMESTAMP}" "${ARCH_NAME}" > image_id.txt
                                    
                                    IMAGE_ID=\$(cat image_id.txt)
                                    echo "Created Image ID: \$IMAGE_ID"
                                    
                                    # Tagging con Buildah
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
                                // Usiamo PODMAN per i test (sostituisce docker run)
                                sh """
                                    echo "Testing ${DIST_NAME}-${ARCH_NAME}"
                                    
                                    # Podman run funziona esattamente come docker run
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
                                // Trivy scansiona direttamente il file TAR (più veloce e sicuro senza socket docker)
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
                                
                                # Crea una lista manifest (unisce amd64 e arm64)
                                buildah manifest rm ${BASENAME}:${dist} || true
                                buildah manifest create ${BASENAME}:${dist}
                                
                                # Aggiungi le immagini precedentemente pushate
                                buildah manifest add ${BASENAME}:${dist} docker://${BASENAME}:${dist}-amd64
                                buildah manifest add ${BASENAME}:${dist} docker://${BASENAME}:${dist}-arm64
                                
                                # Push del manifest completo
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
        
        // Report e Post actions rimangono uguali al tuo vecchio file
        stage('Generate Report') {
             steps {
                container('builder') {
                    // Solo una piccola modifica qui: usare 'buildah images' invece di 'docker images'
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
                // Pulizia Buildah
                sh 'buildah rm --all || true'
                sh 'buildah rmi --prune || true'
            }
        }
    }
}
