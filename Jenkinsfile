#!groovy
import groovy.json.JsonSlurperClassic

node {
    def BUILD_NUMBER="1.0"
    def RUN_ARTIFACT_DIR="tests\\${BUILD_NUMBER}"
    def SFDC_USERNAME

    def HUB_ORG = env.HUB_ORG_DH
    def SFDC_HOST = env.SFDC_HOST_DH
    def JWT_KEY_CRED_ID = env.JWT_CRED_ID_DH
    def CONNECTED_APP_CONSUMER_KEY = env.CONNECTED_APP_CONSUMER_KEY_DH

    def toolbelt = "sfdx"

    println 'KEY IS' 
    println JWT_KEY_CRED_ID
    println HUB_ORG
    println SFDC_HOST
    println CONNECTED_APP_CONSUMER_KEY

    stage('checkout source') {
        // when running in multi-branch job, one must issue this command
        checkout scm
    }

    withCredentials([file(credentialsId: JWT_KEY_CRED_ID, variable: 'jwt_key_file')]) {
        stage('Create Scratch Org') {

            //if ("${SFDC_USERNAME}" == "") {
                if (isUnix()) {
                    rc = sh returnStatus: true, script: "${toolbelt} force:auth:jwt:grant --clientid ${CONNECTED_APP_CONSUMER_KEY} --username ${HUB_ORG} --jwtkeyfile ${jwt_key_file} --setdefaultdevhubusername --instanceurl ${SFDC_HOST}"
                } else {
                    rc = bat returnStatus: true, script: "${toolbelt} force:auth:jwt:grant --clientid ${CONNECTED_APP_CONSUMER_KEY} --username ${HUB_ORG} --jwtkeyfile \"${jwt_key_file}\" --setdefaultdevhubusername --instanceurl ${SFDC_HOST}"
                }            
                
                if (rc != 0) { error 'hub org authorization failed' }

                // need to pull out assigned username
                if (isUnix()) {
                    rmsg = sh returnStdout: true, script: "${toolbelt} force:org:create --definitionfile config/project-scratch-def.json --json --setdefaultusername"
                } else {
                    rmsg = bat returnStdout: true, script: "${toolbelt} force:org:create --definitionfile config/project-scratch-def.json --json --setdefaultusername"
                }

                println rmsg

                // For Windows, remove leading gibberish (TODO: Use "@echo off")
                if (!isUnix()) {
                    def jsonParsed = rmsg.substring((int) (rmsg.indexOf('\n')+1))
                    rmsg = jsonParsed.substring((int) (jsonParsed.indexOf('\n')+1))
                }

                def jsonSlurper = new JsonSlurperClassic()
                def robj = jsonSlurper.parseText(rmsg)
                if (robj.status != 0) { error 'org creation failed: ' + robj.message }
                SFDC_USERNAME=robj.result.username
                robj = null
            //}
        }

        stage('Push To Test Org') {
            if (isUnix()) {
                rc = sh returnStatus: true, script: "${toolbelt} force:source:push --targetusername ${SFDC_USERNAME}"
            } else {
                rc = bat returnStatus: true, script: "${toolbelt} force:source:push --targetusername ${SFDC_USERNAME}"
            }
            if (rc != 0) {
                error 'push failed'
            }

            // assign permset
            /*if (isUnix()) {
                rc = sh returnStatus: true, script: "${toolbelt} force:user:permset:assign --targetusername ${SFDC_USERNAME} --permsetname DreamHouse"
            } else {
                rc = bat returnStatus: true, script: "${toolbelt} force:user:permset:assign --targetusername ${SFDC_USERNAME} --permsetname DreamHouse"
            }
            if (rc != 0) {
                error 'permset:assign failed'
            }*/
        }

        stage('Run Apex Test') {
            //bat "mkdir -p ${RUN_ARTIFACT_DIR}"
            timeout(time: 120, unit: 'SECONDS') {
                if(isUnix()) {
                    rc = sh returnStatus: true, script: "${toolbelt} force:apex:test:run --testlevel RunLocalTests --outputdir ${RUN_ARTIFACT_DIR} --resultformat tap --targetusername ${SFDC_USERNAME}"
                } else {
                    rc = bat returnStatus: true, script: "${toolbelt} force:apex:test:run --testlevel RunLocalTests --outputdir ${RUN_ARTIFACT_DIR} --resultformat tap --targetusername ${SFDC_USERNAME}"
                }
                if (rc != 0) {
                    error 'apex test run failed'
                }
            }
        }

        stage('collect results') {
            junit keepLongStdio: true, testResults: 'tests/**/*-junit.xml'
        }

        stage('Run Selenium Test') {
            // TODO: Use TestNG to collect results - check with ASG?
            rc = bat returnStatus: true, script: "cd C:\\Selenium\\testforjenkins && mvn clean install && java -jar .\\target\\seleniumtest-1.0-SNAPSHOT.jar"
        }
    }
}