public with sharing class Amazon_Invocable_Comprehend {
    @InvocableMethod(label='Have Amazon analyze text')
	public static void analyzeLanguage(List<ComprehendRequest> comprehendRequests) {
        
        // Retrieve text
        List<ID> lrIDs = new List<ID>();
		List<String> fields = new List<String>();
        List<String> requests = new List<String>();

        for (ComprehendRequest comprehendRequest : comprehendRequests){
			lrIDs.add(comprehendRequest.recordId);
			fields.add(comprehendRequest.fieldWithSubject);
            fields.add(comprehendRequest.fieldWithDescription);

            requests.add(JSON.serialize(comprehendRequest));
		}

        callAmazonAPI(lrIDs, fields, requests);
    }

    @future(callout=true)
     private static void callAmazonAPI (List<ID> lrIDs, List<String> fields, List<String> requests) {
        List<ComprehendRequest> comprehendRequests = new List<ComprehendRequest>();
        for(String request : requests) {
            comprehendRequests.add((ComprehendRequest)JSON.deserialize(request, ComprehendRequest.class));
        }
        
        String objType = id.valueOf(comprehendRequests[0].recordId).getSObjectType().getDescribe().getName();
		String soql = 'SELECT id, ' + String.join(fields, ', ') + ' FROM ' + objType +' WHERE id in :lrIDs';
		System.debug(soql);

        List<SObject> records = Database.query(String.escapeSingleQuotes(soql));
		System.debug(records);

        Map<Id, SObject> recordMap = new Map<Id, SObject>();
		for (SObject record : records){
			recordMap.put((Id)record.get('Id'), record);
		}
		System.debug(recordMap);

        List<Case> toUpdate = new List<Case>();
        AssignmentRule assignRule = [SELECT Id FROM AssignmentRule WHERE SObjectType = 'Case' AND Active = True LIMIT 1];

        for (ComprehendRequest comprehendRequest : comprehendRequests){
			// Make sure to set the right values to send in the request
            comprehendRequest.objectType = objType;
            comprehendRequest.subjectText = String.valueOf(recordMap.get(comprehendRequest.recordId).get(comprehendRequest.fieldWithSubject));
            comprehendRequest.descriptionText = String.valueOf(recordMap.get(comprehendRequest.recordId).get(comprehendRequest.fieldWithDescription));

            Map<String, Object> responseMap = new Map<String, Object>();
            
            try {
                String url = 'https://2osg2qiehh.execute-api.us-east-2.amazonaws.com/default/ClassificationFunction';
                
                HttpRequest request = new HttpRequest();
                request.setEndpoint(url);
                request.setMethod('POST');
                request.setHeader('Content-Type', 'application/json');
                request.setHeader('x-api-key', 'x04FmSqEZW3N94n1aXCrWaLfLruHlerH4qRrf9Mp');
                request.setBody('{"description":' + comprehendRequest.descriptionText + ', "subject":' + comprehendRequest.subjectText + '}');
                
                HttpResponse response = new Http().send(request);
                
                if (response.getStatusCode() == 200) {
                    String responseStr = response.getBody();
                    System.debug('Response str : ' + responseStr);
                    responseMap = ((Map<String, Object>)JSON.deserializeUntyped(response.getBody()));
                } else { 
                    System.debug('Error reponse: ' + response.getBody()); 
                    throw new CalloutException( response.getBody() );
                } 
                
            } catch (System.Exception e) {
                System.debug('Error occured: '+ e);
                throw e;
            }

            // Process the API response
            ComprehendResponse apiResponse = new ComprehendResponse();
            apiResponse.status = String.valueOf(responseMap.get('status'));
            apiResponse.sentiment = String.valueOf(responseMap.get('sentiment'));
            apiResponse.language = String.valueOf(responseMap.get('language'));
            apiResponse.classification = String.valueOf(responseMap.get('classification'));

            // Update the SObject based on Response
            Case caseRecord = (Case) recordMap.get(comprehendRequest.recordId);
            caseRecord.put(comprehendRequest.labelStoreCategory, apiResponse.classification);
            caseRecord.put(comprehendRequest.labelStoreLanguage, apiResponse.language);
            caseRecord.put(comprehendRequest.labelStoreSentiment, apiResponse.sentiment);
            
            //Creating the DMLOptions for "Assign using active assignment rules" checkbox
            Database.DMLOptions dmlOpts = new Database.DMLOptions();
            dmlOpts.assignmentRuleHeader.assignmentRuleId = assignRule.Id;

            caseRecord.Status = apiResponse.status;
            caseRecord.setOptions(dmlOpts);
            toUpdate.add(caseRecord);
        }

        update toUpdate;
    }

    public class ComprehendRequest {
		@InvocableVariable (required=true label='RecordId of record to analyze')
		public String recordId;

		@InvocableVariable (required=true label='Field containing Subject')
		public String fieldWithSubject;

		@InvocableVariable (required=true label='Field containing Description')
		public String fieldWithDescription;

		@InvocableVariable (required=true label='Field to Store Category' description='The top label will be stored in this text field')
		public String labelStoreCategory;

        @InvocableVariable (required=true label='Field to Store Sentiment' description='The top label will be stored in this text field')
		public String labelStoreSentiment;

        @InvocableVariable (required=true label='Field to Store Language' description='The top label will be stored in this text field')
		public String labelStoreLanguage;

        public String objectType;
        public String subjectText;
        public String descriptionText;
	}

    public class ComprehendResponse {
        public String status {get; set;}
        public String sentiment {get; set;}
        public String language {get; set;}
        public String classification {get; set;}
    }

}
