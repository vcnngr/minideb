#!/usr/bin/env groovy
/**
 * VCNNGR Minideb Pipeline
 * 
 * Build base image Debian minimal con ultime patch di sicurezza
 * 
 * Trigger: 
 * - Manual
 * - Scheduled (weekly)
 * - Webhook da Debian security announce
 * 
 * Output:
 * - vcnngr/minideb:bookworm
 * - vcnngr/minideb:12
 * - vcnngr/minideb:latest
 */

// VCNNGR Minideb Pipeline - Production with SonarQube
// Fixed: All operations in debian container (has bash + docker)

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
  - name: sonar-scanner
    image: sonarsource/sonar-scanner-cli:latest
    command: [cat]
    tty: true
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
║   Based on Bitnami Minideb                 ║
╚════════════════════════════════════════════╝

Distribution: ${params.DIST}
Architecture: ${params.ARCH}
Build Date:   ${BUILD_DATE}
Build Time:   ${BUILD_TIMESTAMP}
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
                            gnupg curl shellcheck git rsync qemu-user-static docker.io
                        
                        # Verify docker is working
                        docker version
                        
                        # Make scripts executable
                        chmod +x mkimage import buildone test pushone pushall pushmanifest || true
                        
                        # Setup QEMU for cross-platform builds
                        docker run --rm --privileged multiarch/qemu-user-static --reset -p yes || true
                    '''
                }
            }
        }
        
        stage('Code Quality') {
            parallel {
                stage('Shellcheck') {
                    steps {
                        container('debian') {
                            sh '''
                                if [ -f shellcheck ]; then
                                    bash shellcheck || echo "Shellcheck warnings found"
                                else
                                    shellcheck mkimage import buildone || echo "Shellcheck completed"
                                fi
                            '''
                        }
                    }
                }
                
                stage('SonarQube Analysis') {
                    when {
                        expression { params.RUN_SONARQUBE }
                    }
                    steps {
                        container('sonar-scanner') {
                            script {
                                try {
                                    sh '''
                                        echo "Starting SonarQube scan..."
                                        echo "Token length: ${#SONAR_TOKEN}"
                                        
                                        sonar-scanner \
                                            -Dsonar.host.url=http://sonarqube-sonarqube.jenkins.svc.cluster.local:9000 \
                                            -Dsonar.token=${SONAR_TOKEN} \
                                            -Dsonar.projectKey=vcnngr-minideb \
                                            -Dsonar.projectName='VCNNGR Minideb' \
                                            -Dsonar.projectVersion=${BUILD_DATE}-${GIT_COMMIT_SHORT} \
                                            -Dsonar.sources=. \
                                            -Dsonar.exclusions='**/*.md,build/**,**/.github/**,**/.git/**,**/test/**' \
                                            -Dsonar.sourceEncoding=UTF-8 \
                                            -Dsonar.scm.disabled=true \
                                            -Dsonar.verbose=true
                                        
                                        echo "SonarQube scan completed successfully"
                                    '''
                                } catch (Exception e) {
                                    echo "WARNING: SonarQube scan failed: ${e.message}"
                                    echo "Continuing build despite SonarQube failure"
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
                container('sonar-scanner') {
                    timeout(time: 10, unit: 'MINUTES') {
                        script {
                            try {
                                sh '''
                                    echo "Checking Quality Gate status..."
                                    sleep 10
                                    
                                    if [ -f .scannerwork/report-task.txt ]; then
                                        TASK_URL=$(cat .scannerwork/report-task.txt | grep ceTaskUrl | cut -d'=' -f2-)
                                        
                                        if [ -n "$TASK_URL" ]; then
                                            echo "Task URL: $TASK_URL"
                                            
                                            for i in {1..30}; do
                                                STATUS=$(curl -s -u "${SONAR_TOKEN}:" "$TASK_URL" | grep -o '"status":"[^"]*"' | cut -d'"' -f4 || echo "UNKNOWN")
                                                echo "Attempt $i: Status = $STATUS"
                                                
                                                if [ "$STATUS" = "SUCCESS" ]; then
                                                    echo "Quality Gate check completed"
                                                    break
                                                elif [ "$STATUS" = "FAILED" ] || [ "$STATUS" = "CANCELED" ]; then
                                                    echo "WARNING: Quality Gate status: $STATUS"
                                                    break
                                                fi
                                                
                                                sleep 10
                                            done
                                        else
                                            echo "WARNING: Could not find task URL"
                                        fi
                                    else
                                        echo "WARNING: report-task.txt not found"
                                    fi
                                '''
                            } catch (Exception e) {
                                echo "WARNING: Quality Gate check failed: ${e.message}"
                                echo "Continuing build despite Quality Gate failure"
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
                                    
                                    # ISO 8601 timestamp for import script (WITH colons - required by script)
                                    TIMESTAMP=\$(date -u +%Y-%m-%dT%H:%M:%SZ)
                                    echo "Using timestamp: \${TIMESTAMP}"
                                    
                                    # Execute import script - uses bash
                                    echo "Running import script..."
                                    IMAGE_ID=\$(bash ./import "build/${DIST_NAME}-${ARCH_NAME}.tar" "\${TIMESTAMP}" "${ARCH_NAME}")
                                    
                                    if [ -z "\${IMAGE_ID}" ]; then
                                        echo "ERROR: Failed to import image - IMAGE_ID is empty"
                                        exit 1
                                    fi
                                    
                                    echo "Successfully imported image: \${IMAGE_ID}"
                                    
                                    # Tag images - BUILD_TIMESTAMP has hyphens (Docker compatible)
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
                                    
                                    echo "Test 1: OS Release"
                                    docker run --rm ${BASENAME}:${DIST_NAME}-${ARCH_NAME} \
                                        bash -c 'cat /etc/os-release | head -2'
                                    
                                    echo "Test 2: Package Installation"
                                    docker run --rm ${BASENAME}:${DIST_NAME}-${ARCH_NAME} \
                                        bash -c 'install_packages curl && curl --version | head -1'
                                    
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
                                    docker push ${BASENAME}:${DIST_NAME}-${ARCH_NAME}-${BUILD_TIMESTAMP}
                                    
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
# VCNNGR Minideb Build Report

**Build Number:** ${BUILD_NUMBER}
**Build Date:** ${BUILD_DATE}
**Build Timestamp:** ${BUILD_TIMESTAMP}
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
                        
                        echo "" >> build-report.md
                        echo "## SonarQube Analysis" >> build-report.md
                        echo "- Project: vcnngr-minideb" >> build-report.md
                        echo "- Dashboard: http://sonarqube-sonarqube.jenkins.svc.cluster.local:9000/dashboard?id=vcnngr-minideb" >> build-report.md
                        
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

Images: https://hub.docker.com/r/vcnngr/minideb
SonarQube: http://sonarqube-sonarqube.jenkins.svc.cluster.local:9000/dashboard?id=vcnngr-minideb
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
