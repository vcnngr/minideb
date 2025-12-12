pipeline {
    // AGENT NONE: Non creiamo un pod "master" globale. 
    // I pod verranno creati dinamicamente dentro la matrice.
    agent none
    
    environment {
        BASENAME = 'vcnngr/minideb'
        DOCKER_REGISTRY = 'docker.io'
        LATEST = 'trixie'
        
        // Credenziali globali
        DOCKERHUB = credentials('dockerhub-credentials')
        SONAR_TOKEN = credentials('sonarqube-token')
        
        GIT_COMMIT_SHORT = sh(returnStdout: true, script: 'git rev-parse --short HEAD').trim()
        BUILD_DATE = sh(returnStdout: true, script: 'date -u +%Y%m%d').trim()
        BUILD_TIMESTAMP = sh(returnStdout: true, script: 'date -u +%Y-%m-%dT%H:%M-%S').trim()
    }
    
    options {
        buildDiscarder(logRotator(numToKeepStr: '30'))
        timestamps()
        // Timeout globale di sicurezza
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
                
                // DEFINIZIONE AGENT DINAMICO PER OGNI CELLA
                // Ogni combinazione Distro/Arch avrà il suo Pod isolato
                agent {
                    kubernetes {
                        // Label univoca per distinguere i pod nel log di Jenkins
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
  
  # CRUCIALE: Ogni Pod deve assicurarsi che QEMU sia attivo sul nodo in cui atterra
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
      # Richiesta "soft" bassa per permettere al cluster di schedulare i pod
      # Limite "hard" alto per permettere a QEMU di usare la CPU se disponibile
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
                    expression {
                        // Filtro opzionale se vuoi testare solo una architettura specifica
                        // env.BUILD_DISTS.split(',').contains(DIST_NAME) 
                        return true
                    }
                }
                
                stages {
                    stage('Build & Push') {
                        steps {
                            container('builder') {
                                // 1. SETUP AMBIENTE
                                sh '''
                                    echo ">>> SETUP ENVIRONMENT (${DIST_NAME}-${ARCH_NAME})"
                                    apt-get update -qq
                                    apt-get install -y -qq buildah podman qemu-user-static debootstrap jq curl git dpkg-dev perl debian-archive-keyring > /dev/null
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
                                    ./import-buildah "build/${DIST_NAME}-${ARCH_NAME}.tar" "${BUILD_TIMESTAMP}" "${ARCH_NAME}" > image_id.txt
                                    
                                    IMAGE_ID=\$(cat image_id.txt)
                                    echo "Image ID: \$IMAGE_ID"
                                    
                                    buildah tag \$IMAGE_ID ${BASENAME}:${DIST_NAME}-${ARCH_NAME}
                                    buildah tag \$IMAGE_ID ${BASENAME}:${DIST_NAME}-${ARCH_NAME}-${BUILD_DATE}
                                    buildah tag \$IMAGE_ID ${BASENAME}:${DIST_NAME}-${ARCH_NAME}-${BUILD_TIMESTAMP}
                                    
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
                                // Nota: Trivy gira in un altro container nello stesso pod
                            } // fine container builder
                            
                            // Cambio container per Trivy
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
                            
                            // Torno al builder per il Push
                            container('builder') {
                                script {
                                    if (params.PUSH_TO_REGISTRY) {
                                        echo ">>> PUSH TO REGISTRY"
                                        // Usa \$ per evitare interpolazione insicura di Groovy
                                        sh """
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
        
        // Questo stage crea i MANIFEST (multi-arch).
        // Deve girare DOPO che la matrice ha finito tutto.
        // Ha bisogno di un suo pod separato perché quelli della matrice sono stati distrutti.
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
    # Qui possiamo usare l'immagine buildah upstream che è più leggera, 
    # tanto non dobbiamo compilare nulla, solo fare manifest push
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
                                
                                # Aggiungiamo le immagini che abbiamo pushato nello stage precedente
                                buildah manifest add ${BASENAME}:${dist} docker://${BASENAME}:${dist}-amd64
                                buildah manifest add ${BASENAME}:${dist} docker://${BASENAME}:${dist}-arm64
                                
                                buildah manifest push --all ${BASENAME}:${dist} docker://${BASENAME}:${dist}
                            """
                        }
                        
                        // Gestione speciale per 'latest'
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
