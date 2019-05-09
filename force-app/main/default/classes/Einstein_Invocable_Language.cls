public with sharing class Einstein_Invocable_Language {

	@InvocableMethod(label='Have Einstein analyze text')
	public static void analyzeLanguage(List<LanguageRequest> languageRequests) {

		//don't allow this run in future, batch, or queueable
		if (system.isFuture() || system.isBatch() || system.isQueueable()){
			return;
		}

		List<String> singleBatch = new List<String>();
		List<List<String>> batches = new List<List<String>>();

		Integer batchSize = Limits.getLimitCallouts()-1; //because we'll use a call to get a token for each batch

		//get the actual text
		List<LanguageRequest> deduped = dedupeLRs(languageRequests);
		List<ID> lrIDs = new List<ID>();
		List<String> fields = new List<String>();

		for (LanguageRequest languageRequest : deduped){
			lrIDs.add(languageRequest.recordId);
			fields.add(languageRequest.fieldToAnalyze);
		}

		String objType = id.valueOf(deduped[0].recordId).getSObjectType().getDescribe().getName();
		String soql = 'SELECT id, ' + String.join(fields, ', ') + ' FROM ' + objType +' WHERE id in :lrIDs';
		system.debug(soql);

		List<SObject> records = Database.query(String.escapeSingleQuotes(soql));
		system.debug(records);

		map<id, SObject> recordMap = new map<id, SObject>();
		for (SObject so:records){
			recordMap.put((id)so.get('Id'), so);
		}

		system.debug(recordMap);

		for (LanguageRequest languageRequest : deduped){
			languageRequest.objectType = objType;
			languageRequest.actualText = String.valueOf(recordMap.get(languageRequest.recordId).get(languageRequest.fieldToAnalyze));
			//batch is full, put it in the batch list, blank it for new adds
			if (singleBatch.size()==batchsize){
				Batches.add(singleBatch);
				singleBatch = new List<String>();
			}
			singleBatch.add(JSON.serialize(languageRequest));
		}

		Batches.add(singleBatch);
		for (List<String> batch:batches){
			getAnalysis(batch);
		}
	}

	@future(callout=true)
	public static void getAnalysis(List<String> input){

		List<ID> lrIDs = new List<ID>();
		set<String> fields = new set<String>();

		List<LanguageRequest> languageRequests = new List<LanguageRequest>();

		for (String s:input){
			languageRequests.add((LanguageRequest)JSON.deserialize(s, LanguageRequest.class));
		}

		for (LanguageRequest languageRequest : languageRequests){
			lrIDs.add(languageRequest.recordId);

			fields.add(languageRequest.labelStoreField);
			if (languageRequest.probabilityStoreField != null){
				fields.add(languageRequest.probabilityStoreField);
			}
			if (languageRequest.rawStoreField != null){
				fields.add(languageRequest.rawStoreField);
			}
            if (languageRequest.modelType=='Sentiment'){
                Einstein_PredictionService service = new Einstein_PredictionService(Einstein_PredictionService.Types.SENTIMENT);
                languageRequest.prediction = service.predictSentiment(languageRequest.modelId, languageRequest.actualText, 0, '');
            } else if (languageRequest.modelType=='Intent'){
                Einstein_PredictionService service = new Einstein_PredictionService(Einstein_PredictionService.Types.INTENT);
                languageRequest.prediction = service.predictIntent(languageRequest.modelId, languageRequest.actualText, 0, '');
            } else if (languageRequest.modelId == null && (languageRequest.modelType=='Sentiment' || languageRequest.modelType==null)){
                //default this
                Einstein_PredictionService service = new Einstein_PredictionService(Einstein_PredictionService.Types.SENTIMENT);
                languageRequest.prediction = service.predictSentiment('CommunitySentiment', languageRequest.actualText, 0, '');
            }
			system.debug(languageRequest);
		}

		List<String> fieldNames = new List<String>(fields);

		String soql = 'SELECT id, ' + String.join(fieldNames, ', ') + ' FROM ' + languageRequests[0].objectType +' WHERE id in :lrIDs';
		system.debug(soql);

		List<SObject> records = Database.query(String.escapeSingleQuotes(soql));
		system.debug(records);

		map<id, SObject> recordMap = new map<id, SObject>();
		for (SObject so:records){
			recordMap.put((id)so.get('Id'), so);
		}

		system.debug(recordMap);
		//handle the predictions and update that record
		for (LanguageRequest languageRequest : languageRequests){
			recordMap.get((id)languageRequest.recordId).put(languageRequest.labelStoreField, languageRequest.prediction.probabilities[0].label);
			//TODO: probability, raw, chatter
			if (languageRequest.probabilityStoreField != null){
				try{
					recordMap.get((id)languageRequest.recordId).put(languageRequest.probabilityStoreField, languageRequest.prediction.probabilities[0].probability);
				} catch (SObjectException e){
					//might be a text field instead of decimal?
						recordMap.get((id)languageRequest.recordId).put(languageRequest.probabilityStoreField, String.valueOf(languageRequest.prediction.probabilities[0].probability));
				}
			}
			if (languageRequest.rawStoreField != null){
                // we don't need the coordinates property for anything besides object detection!
				recordMap.get((id)languageRequest.recordId).put(languageRequest.rawStoreField, JSON.serialize(languageRequest.prediction).remove(',"boundingBox":null'));
			}
		}

		List<SObject> output = recordMap.values();
		Database.update(output);

	}

	public class LanguageRequest {
		@InvocableVariable (required=true label='recordId of record to Analyze')
		public String recordId;

		@InvocableVariable (required=true label='Field to Analyze')
		public String fieldToAnalyze;

		@InvocableVariable (required=true label='Field to Store Answer' description='The top label will be stored in this text field')
		public String labelStoreField;

		@InvocableVariable (label='Field to Store Probability' description='The probability on the top label will be stored in this number/percentage field')
		public String probabilityStoreField;

		@InvocableVariable (label='Field to Store Raw Results' description='This text field will get all predictions (label/probability pairs) stored as JSON')
		public String rawStoreField;

		@InvocableVariable (label='Model Id' description='Model Id from Einstein (not the Salesforce ID)')
		public String modelId;

		@InvocableVariable (label='Model Type' description='Allowed values are Sentiment and Intent')
		public String modelType;

		public String actualText;
		public String objectType;

		public Einstein_PredictionResult prediction;
	}

	public static List<LanguageRequest> dedupeLRs(List<LanguageRequest> input){
		set<LanguageRequest> temp = new set<LanguageRequest>(input);
		return new List<LanguageRequest>(temp);
	}

}