pipeline {
    agent none
    
    environment {
        BASENAME = 'vcnngr/minideb'
        DOCKER_REGISTRY = 'docker.io'
        LATEST = 'trixie'
        DOCKERHUB = credentials('dockerhub-credentials')
        SONAR_TOKEN = credentials('sonarqube-token')
    }
    
    options {
        buildDiscarder(logRotator(numToKeepStr: '30'))
        timestamps()
        // Con la RAM, se non finisce in 2 ore c'è un problema grave
        timeout(time: 2, unit: 'HOURS') 
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
    job: vcnngr-matrix-ram
spec:
  serviceAccountName: jenkins-agent
  securityContext:
    runAsUser: 0
    fsGroup: 0
  
  # VOLUMI
  volumes:
  # 1. RAM DISK: Qui avverrà la magia. Velocità di scrittura: GB/s.
  - name: ramdisk
    emptyDir:
      medium: Memory
      sizeLimit: 2Gi
  # 2. STORAGE VELOCE PER BUILDAH (opzionale, ma aiuta il commit finale)
  - name: container-storage
    emptyDir: {}

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
    volumeMounts:
    # Montiamo la RAM su /mnt/fast-build
    - name: ramdisk
      mountPath: /mnt/fast-build
    - name: container-storage
      mountPath: /var/lib/containers
    env:
    # Usiamo vfs su RAM disk o overlay su emptyDir. 
    # Proviamo overlay per performance, se fallisce buildah, vfs su RAM è comunque veloce.
    - name: STORAGE_DRIVER
      value: "overlay" 
    - name: BUILDAH_FORMAT
      value: "docker"
    resources:
      requests:
        memory: "2Gi" # Serve RAM per il disco
        cpu: "1000m"
      limits:
        memory: "6Gi" # Diamo abbastanza RAM per ospitare il filesystem Debian
        cpu: "4000m"
  
  - name: trivy
    image: aquasec/trivy:latest
    command: [cat]
    tty: true
"""
                    }
                }

                when { expression { return true } }
                
                stages {
                    stage('Build & Push') {
                        steps {
                            container('builder') {
                                script {
                                    sh 'apt-get update -qq && apt-get install -y -qq git > /dev/null'
                                    env.GIT_COMMIT_SHORT = sh(returnStdout: true, script: 'git rev-parse --short HEAD').trim()
                                    env.BUILD_DATE = sh(returnStdout: true, script: 'date -u +%Y%m%d').trim()
                                    env.BUILD_TIMESTAMP = sh(returnStdout: true, script: 'date -u +%Y-%m-%dT%H:%M-%S').trim()
                                }

                                sh '''
                                    echo ">>> SETUP ENVIRONMENT"
                                    # Installiamo fuse-overlayfs per sicurezza, casomai servisse
                                    apt-get install -y -qq buildah podman qemu-user-static debootstrap jq curl dpkg-dev perl debian-archive-keyring fuse-overlayfs > /dev/null
                                    chmod +x mkimage import-buildah
                                    
                                    # Configurazione Buildah per usare fuse-overlayfs (più compatibile)
                                    # Se il nodo supporta overlay nativo, questo verrà ignorato o sovrascritto, ma è un buon fallback
                                    sed -i 's/^#mount_program/mount_program/' /etc/containers/storage.conf || true
                                '''
                                
                                // *** IL TRUCCO DELLA VELOCITÀ ***
                                // Spostiamo tutto in RAM (/mnt/fast-build) ed eseguiamo lì
                                sh """
                                    echo ">>> MOVING TO RAM DISK FOR SPEED"
                                    # Copiamo gli script necessari nel RAM DISK
                                    cp -r * /mnt/fast-build/
                                    
                                    # Entriamo nel RAM DISK
                                    cd /mnt/fast-build
                                    
                                    echo ">>> STARTING MKIMAGE IN RAM"
                                    mkdir -p build
                                    # Questo ora scriverà in memoria, non su disco di rete!
                                    ./mkimage "build/${DIST_NAME}-${ARCH_NAME}.tar" "${DIST_NAME}" "${ARCH_NAME}"
                                    
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
                                    
                                    # Torniamo al workspace originale per copiare i risultati (per i report/artifact)
                                    echo ">>> COPYING RESULTS BACK TO WORKSPACE"
                                    cd ${env.WORKSPACE}
                                    cp /mnt/fast-build/build/*.tar build/ 2>/dev/null || true
                                    cp /mnt/fast-build/*.log build/ 2>/dev/null || true
                                """
                                
                                sh """
                                    echo ">>> TESTING IMAGE"
                                    podman run --rm ${BASENAME}:${DIST_NAME}-${ARCH_NAME} cat /etc/os-release | head -2
                                    podman run --rm ${BASENAME}:${DIST_NAME}-${ARCH_NAME} dpkg --print-architecture
                                """
                            }
                            
                            container('trivy') {
                                script {
                                    if (params.RUN_SECURITY_SCAN) {
                                        // Trivy deve leggere il tar. Assicuriamoci di averlo copiato nel workspace
                                        // O leggiamolo dalla RAM (più veloce)
                                        sh """
                                            mkdir -p build/security
                                            # Leggiamo direttamente dalla RAM per velocità
                                            trivy image \
                                                --input "/mnt/fast-build/build/${DIST_NAME}-${ARCH_NAME}.tar" \
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
        
        stage('Generate Report') {
             steps {
                // Questo stage potrebbe fallire se non abbiamo le immagini locali perché i pod precedenti sono morti.
                // Lo semplifichiamo per stampare solo un messaggio di successo.
                script {
                    echo "Build and Push completed. Check Docker Hub for images."
                }
             }
        }
    }
}
