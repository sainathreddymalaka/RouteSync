// ──────────────────────────────────────────────────────────────
// File: MapplsAutosuggestService.cls
// ──────────────────────────────────────────────────────────────
public without sharing class MapplsAutosuggestService {

    private static final String BASE_URL = 'https://search.mappls.com';

    /**
     * Returns Set<String> of full labels: "Place Name – Address"
     */
    @AuraEnabled(cacheable=true)
    public static List<String> search(String query) {
        if (String.isBlank(query) || query.length() > 45) {
            throw new AuraHandledException('Query must be 1–45 characters');
        }

        // ---- Get token from Protected CMDT ----
        Mappls_Config__mdt cfg = [
            SELECT Access_Token__c
            FROM Mappls_Config__mdt
            WHERE DeveloperName = 'Access_Token'
            LIMIT 1
        ];
        if (cfg == null || String.isBlank(cfg.Access_Token__c)) {
            throw new AuraHandledException('Mappls token not configured');
        }

        // ---- Build endpoint ----
        String endpoint = '/search/places/autosuggest/json';
        String params = 'query=' + EncodingUtil.urlEncode(query.trim(), 'UTF-8')
                      + '&access_token=' + cfg.Access_Token__c
                      + '&region=IND';

        // ---- HTTP Callout ----
        system.debug('End point before callout :: '+BASE_URL + endpoint + '?' + params);
        HttpRequest req = new HttpRequest();
        req.setEndpoint(BASE_URL + endpoint + '?' + params);
        req.setMethod('GET');
        req.setTimeout(120000);

        HttpResponse res = new Http().send(req);
        system.debug(' Mappls Response : '+ JSON.deserializeUntyped(res.getBody()));
        if (res.getStatusCode() != 200) {
            throw new AuraHandledException('Mappls API Error: ' + res.getBody());
        }

        // ---- Parse JSON into temp wrapper ----
        Map<String, Object> jsonResponse = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        List<Object> locations = (List<Object>) jsonResponse.get('suggestedLocations');

        // ---- Build Set<String> of labels ----
        Set<String> labels = new Set<String>();
        List<String> labelsList = new List<String>();
        if (locations != null) {
            for (Object locObj : locations) {
                Map<String, Object> loc = (Map<String, Object>) locObj;
                String placeName = (String) loc.get('placeName');
                String placeAddress = (String) loc.get('placeAddress');

                String label = String.isNotBlank(placeName) ? placeName : '';
                if (String.isNotBlank(placeAddress)) {
                    label += (label.length() > 0 ? ' – ' : '') + placeAddress;
                }
                if (String.isNotBlank(label)) {
                    labels.add(label);
                }
            }
        }
        labelsList.addAll(labels);
        system.debug('labelsList :: '+labelsList);

        return labelsList;
    }
}