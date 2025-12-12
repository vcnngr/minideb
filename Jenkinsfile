pipeline {
    // AGENT NONE: I pod vengono creati dinamicamente nella matrix
    agent none
    
    environment {
        BASENAME = 'vcnngr/minideb'
        DOCKER_REGISTRY = 'docker.io'
        LATEST = 'trixie'
        
        // Credenziali globali (queste funzionano anche senza agent)
        DOCKERHUB = credentials('dockerhub-credentials')
        SONAR_TOKEN = credentials('sonarqube-token')
        
        // RIMOSSI GLI 'sh' DA QUI PERCHE' CAUSAVANO L'ERRORE
    }
    
    options {
        buildDiscarder(logRotator(numToKeepStr: '30'))
        timestamps()
        timeout(time: 6, unit: 'HOURS')
        ansiColor('xterm')
    }
    
    stages {
        stage('Build Matrix') {
            matrix {
                axes {
                    axis { name 'DIST_NAME'; values 'bullseye', 'bookworm', 'trixie' }
                    axis { name 'ARCH_NAME'; values 'amd64', 'arm64' }
                }
                
                agent {
                    kubernetes {
                        label "builder-${DIST_NAME}-${ARCH_NAME}-${UUID.randomUUID().toString()}"
                        yaml """
apiVersion: v1
kind: Pod
metadata:
  labels:
    jenkins: agent
    job: vcnngr-matrix
spec:
  serviceAccountName: jenkins-agent
  securityContext:
    runAsUser: 0
    fsGroup: 0
  
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
    resources:
      requests:
        memory: "1Gi"
        cpu: "1000m"
      limits:
        memory: "4Gi"
        cpu: "4000m"
  
  - name: trivy
    image: aquasec/trivy:latest
    command: [cat]
    tty: true
"""
                    }
                }

                when {
                    expression { return true }
                }
                
                stages {
                    stage('Build & Push') {
                        steps {
                            container('builder') {
                                // *** FIX QUI: Calcoliamo le variabili dentro il container ***
                                script {
                                    echo ">>> CALCULATING DYNAMIC VARIABLES"
                                    // Installiamo git prima di usarlo (se non presente)
                                    sh 'apt-get update -qq && apt-get install -y -qq git > /dev/null'
                                    
                                    env.GIT_COMMIT_SHORT = sh(returnStdout: true, script: 'git rev-parse --short HEAD').trim()
                                    env.BUILD_DATE = sh(returnStdout: true, script: 'date -u +%Y%m%d').trim()
                                    env.BUILD_TIMESTAMP = sh(returnStdout: true, script: 'date -u +%Y-%m-%dT%H:%M-%S').trim()
                                    
                                    echo "Build Info: ${env.BUILD_DATE} - ${env.GIT_COMMIT_SHORT}"
                                }

                                // 1. SETUP AMBIENTE
                                sh '''
                                    echo ">>> SETUP ENVIRONMENT (${DIST_NAME}-${ARCH_NAME})"
                                    # Git lo abbiamo già installato sopra, installiamo il resto
                                    apt-get install -y -qq buildah podman qemu-user-static debootstrap jq curl dpkg-dev perl debian-archive-keyring > /dev/null
                                    chmod +x mkimage import-buildah
                                '''
                                
                                // 2. CREATE BASE IMAGE (mkimage)
                                sh """
                                    echo ">>> CREATE ROOTFS"
                                    mkdir -p build
                                    ./mkimage "build/${DIST_NAME}-${ARCH_NAME}.tar" "${DIST_NAME}" "${ARCH_NAME}"
                                """
                                
                                // 3. IMPORT TO BUILDAH
                                sh """
                                    echo ">>> IMPORTING TARBALL"
                                    ./import-buildah "build/${DIST_NAME}-${ARCH_NAME}.tar" "${env.BUILD_TIMESTAMP}" "${ARCH_NAME}" > image_id.txt
                                    
                                    IMAGE_ID=\$(cat image_id.txt)
                                    echo "Image ID: \$IMAGE_ID"
                                    
                                    buildah tag \$IMAGE_ID ${BASENAME}:${DIST_NAME}-${ARCH_NAME}
                                    buildah tag \$IMAGE_ID ${BASENAME}:${DIST_NAME}-${ARCH_NAME}-${env.BUILD_DATE}
                                    buildah tag \$IMAGE_ID ${BASENAME}:${DIST_NAME}-${ARCH_NAME}-${env.BUILD_TIMESTAMP}
                                    
                                    if [ "${DIST_NAME}" = "${LATEST}" ]; then
                                        buildah tag \$IMAGE_ID ${BASENAME}:latest-${ARCH_NAME}
                                    fi
                                """
                                
                                // 4. TEST (Podman)
                                sh """
                                    echo ">>> TESTING IMAGE"
                                    podman run --rm ${BASENAME}:${DIST_NAME}-${ARCH_NAME} cat /etc/os-release | head -2
                                    podman run --rm ${BASENAME}:${DIST_NAME}-${ARCH_NAME} dpkg --print-architecture
                                """
                                
                                // 5. SECURITY SCAN (Trivy)
                            } // fine container builder
                            
                            container('trivy') {
                                script {
                                    if (params.RUN_SECURITY_SCAN) {
                                        echo ">>> SECURITY SCAN"
                                        sh """
                                            mkdir -p build/security
                                            trivy image \
                                                --input "build/${DIST_NAME}-${ARCH_NAME}.tar" \
                                                --severity HIGH,CRITICAL \
                                                --format json \
                                                --output build/security/trivy-${DIST_NAME}-${ARCH_NAME}.json || true
                                        """
                                        archiveArtifacts artifacts: 'build/security/*.json', allowEmptyArchive: true
                                    }
                                }
                            }
                            
                            container('builder') {
                                script {
                                    if (params.PUSH_TO_REGISTRY) {
                                        echo ">>> PUSH TO REGISTRY"
                                        sh """
                                            echo \$DOCKERHUB_PSW | buildah login -u \$DOCKERHUB_USR --password-stdin ${DOCKER_REGISTRY}
                                            
                                            buildah push ${BASENAME}:${DIST_NAME}-${ARCH_NAME}
                                            buildah push ${BASENAME}:${DIST_NAME}-${ARCH_NAME}-${env.BUILD_DATE}
                                            buildah push ${BASENAME}:${DIST_NAME}-${ARCH_NAME}-${env.BUILD_TIMESTAMP}
                                            
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
                }
            }
            agent {
                kubernetes {
                    label "manifest-builder"
                    yaml """
apiVersion: v1
kind: Pod
metadata:
  labels:
    job: manifest-creator
spec:
  containers:
  - name: builder
    image: quay.io/buildah/stable:v1.33
    command: [cat]
    tty: true
    securityContext:
      privileged: true
"""
                }
            }
            steps {
                container('builder') {
                    script {
                        def dists = params.DIST == 'all' ? ['bullseye', 'bookworm', 'trixie'] : [params.DIST]
                        
                        sh "echo \$DOCKERHUB_PSW | buildah login -u \$DOCKERHUB_USR --password-stdin ${DOCKER_REGISTRY}"
                        
                        dists.each { dist ->
                            sh """
                                echo "Creating manifest for ${dist}..."
                                buildah manifest rm ${BASENAME}:${dist} || true
                                buildah manifest create ${BASENAME}:${dist}
                                
                                buildah manifest add ${BASENAME}:${dist} docker://${BASENAME}:${dist}-amd64
                                buildah manifest add ${BASENAME}:${dist} docker://${BASENAME}:${dist}-arm64
                                
                                buildah manifest push --all ${BASENAME}:${dist} docker://${BASENAME}:${dist}
                            """
                        }
                        
                        if (dists.contains(env.LATEST)) {
                             sh """
                                echo "Creating manifest for latest..."
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
    }
}
