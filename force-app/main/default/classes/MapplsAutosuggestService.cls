// ──────────────────────────────────────────────────────────────
// File: MapplsAutosuggestService.cls
// Updated: Apr 2026
// Strategy:
//   - Autosuggest: Mappls API (dropdown labels)
//   - Coordinates: OpenStreetMap Nominatim API (free, no key needed)
// ──────────────────────────────────────────────────────────────
public without sharing class MapplsAutosuggestService {

    private static final String SEARCH_BASE   = 'https://search.mappls.com';
    private static final String NOMINATIM_URL = 'https://nominatim.openstreetmap.org/search';

    // ── CONFIG ────────────────────────────────────────────────────────────────

    private static String getAccessToken() {
        Mappls_Config__mdt cfg = [
            SELECT Access_Token__c
            FROM Mappls_Config__mdt
            WHERE DeveloperName = 'Access_Token'
            LIMIT 1
        ];
        if (cfg == null || String.isBlank(cfg.Access_Token__c)) {
            throw new AuraHandledException('Mappls token not configured');
        }
        return cfg.Access_Token__c;
    }

    // ── WRAPPER ───────────────────────────────────────────────────────────────

    public class LocationResult {
        @AuraEnabled public String label;
        @AuraEnabled public String eLoc;
        @AuraEnabled public Double latitude;
        @AuraEnabled public Double longitude;
        @AuraEnabled public String city;
        @AuraEnabled public String state;
        @AuraEnabled public String placeName;
    }

    // ── AUTOSUGGEST: labels only for dropdown ─────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<String> search(String query) {
        if (String.isBlank(query) || query.length() > 45) {
            throw new AuraHandledException('Query must be 1-45 characters');
        }

        String token    = getAccessToken();
        String endpoint = SEARCH_BASE + '/search/places/autosuggest/json'
                        + '?query='        + EncodingUtil.urlEncode(query.trim(), 'UTF-8')
                        + '&access_token=' + token
                        + '&region=IND';

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('GET');
        req.setTimeout(10000);

        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() != 200) {
            throw new AuraHandledException('Mappls API Error: ' + res.getBody());
        }

        Map<String, Object> body      = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        List<Object>        locations = (List<Object>) body.get('suggestedLocations');

        List<String> labels = new List<String>();
        Set<String>  seen   = new Set<String>();

        if (locations != null) {
            for (Object locObj : locations) {
                Map<String, Object> loc          = (Map<String, Object>) locObj;
                String              placeName    = (String) loc.get('placeName');
                String              placeAddress = (String) loc.get('placeAddress');

                String label = String.isNotBlank(placeName) ? placeName : '';
                if (String.isNotBlank(placeAddress)) {
                    label += (label.length() > 0 ? ' \u2013 ' : '') + placeAddress;
                }
                if (String.isNotBlank(label) && !seen.contains(label)) {
                    seen.add(label);
                    labels.add(label);
                }
            }
        }
        return labels;
    }

    // ── AUTOSUGGEST + NOMINATIM GEOCODE ──────────────────────────────────────
    // Returns Mappls suggestions with coordinates resolved via Nominatim

    @AuraEnabled
    public static List<LocationResult> searchWithCoordinates(String query) {
        if (String.isBlank(query) || query.length() > 45) {
            throw new AuraHandledException('Query must be 1-45 characters');
        }

        String token = getAccessToken();

        // Step 1: Mappls autosuggest for labels
        String autosuggestUrl = SEARCH_BASE + '/search/places/autosuggest/json'
                              + '?query='        + EncodingUtil.urlEncode(query.trim(), 'UTF-8')
                              + '&access_token=' + token
                              + '&region=IND';

        HttpRequest req1 = new HttpRequest();
        req1.setEndpoint(autosuggestUrl);
        req1.setMethod('GET');
        req1.setTimeout(10000);

        HttpResponse res1 = new Http().send(req1);
        if (res1.getStatusCode() != 200) {
            throw new AuraHandledException('Mappls error: ' + res1.getBody());
        }

        Map<String, Object> body      = (Map<String, Object>) JSON.deserializeUntyped(res1.getBody());
        List<Object>        locations = (List<Object>) body.get('suggestedLocations');

        if (locations == null || locations.isEmpty()) return new List<LocationResult>();

        // Build result list from autosuggest
        List<LocationResult> results = new List<LocationResult>();

        for (Object locObj : locations) {
            Map<String, Object> loc          = (Map<String, Object>) locObj;
            String              placeName    = (String) loc.get('placeName');
            String              placeAddress = (String) loc.get('placeAddress');
            String              eLoc         = (String) loc.get('eLoc');

            String label = String.isNotBlank(placeName) ? placeName : '';
            if (String.isNotBlank(placeAddress)) {
                label += (label.length() > 0 ? ' \u2013 ' : '') + placeAddress;
            }
            if (String.isBlank(label)) continue;

            // Parse city/state from placeAddress
            String city = '', state = '';
            if (String.isNotBlank(placeAddress)) {
                List<String> parts = placeAddress.split(',');
                if (parts.size() >= 2) {
                    city  = parts[parts.size() - 2].trim();
                    state = parts[parts.size() - 1].trim();
                } else if (parts.size() == 1) {
                    city = parts[0].trim();
                }
            }

            LocationResult r = new LocationResult();
            r.label     = label;
            r.eLoc      = eLoc;
            r.latitude  = null;
            r.longitude = null;
            r.city      = city;
            r.state     = state;
            r.placeName = placeName;
            results.add(r);
        }

        // Step 2: Nominatim geocode — resolve top result to coordinates
        // We only geocode the first (best) suggestion to save callouts
        if (!results.isEmpty()) {
            LocationResult top = results[0];
            // Build a clean search query: placeName + city
            String geoQuery = top.placeName;
            if (String.isNotBlank(top.city) && !top.city.equalsIgnoreCase(top.placeName)) {
                geoQuery += ', ' + top.city;
            }
            geoQuery += ', India';

            try {
                String nominatimEndpoint = NOMINATIM_URL
                    + '?q='              + EncodingUtil.urlEncode(geoQuery, 'UTF-8')
                    + '&format=json'
                    + '&limit=1'
                    + '&countrycodes=in';

                HttpRequest req2 = new HttpRequest();
                req2.setEndpoint(nominatimEndpoint);
                req2.setMethod('GET');
                req2.setHeader('User-Agent', 'RouteSync-Salesforce/1.0');
                req2.setTimeout(10000);

                HttpResponse res2 = new Http().send(req2);
                System.debug('Nominatim HTTP=' + res2.getStatusCode() + ' body=' + res2.getBody());

                if (res2.getStatusCode() == 200) {
                    List<Object> geoResults = (List<Object>) JSON.deserializeUntyped(res2.getBody());
                    if (!geoResults.isEmpty()) {
                        Map<String, Object> geoResult = (Map<String, Object>) geoResults[0];
                        Double lat = Double.valueOf(String.valueOf(geoResult.get('lat')));
                        Double lon = Double.valueOf(String.valueOf(geoResult.get('lon')));
                        // Apply coordinates to top result and all results with same city
                        // (so nearby suggestions also get approximate coords)
                        top.latitude  = lat;
                        top.longitude = lon;
                        System.debug('Nominatim coords for "' + geoQuery + '": ' + lat + ',' + lon);
                    }
                }
            } catch (Exception ex) {
                System.debug('Nominatim geocode failed: ' + ex.getMessage());
            }
        }

        return results;
    }

    // ── GEOCODE: single query to lat/lng ─────────────────────────────────────
    // Used by searchRides auto-geocode. Tries progressively simpler queries
    // until Nominatim finds a result.

    @AuraEnabled
    public static LocationResult geocode(String query) {
        if (String.isBlank(query)) return null;
        try {
            // Build fallback query list from most specific to least
            List<String> queriesToTry = new List<String>();

            if (query.contains('\u2013')) {
                // Format: "Place Name – Address, City, State, PIN"
                List<String> parts    = query.split('\u2013');
                String placeName      = parts[0].trim();
                String addressPart    = parts.size() > 1 ? parts[1].trim() : '';

                // Try 1: place name + India
                queriesToTry.add(placeName + ', India');

                // Try 2: city — strip PIN codes first, then extract second-to-last segment
                if (String.isNotBlank(addressPart)) {
                    // Remove 6-digit PIN codes before parsing
                    String cleanAddr = addressPart.replaceAll(',?\\s*\\d{6}\\s*', '').trim();
                    if (cleanAddr.endsWith(',')) cleanAddr = cleanAddr.removeEnd(',').trim();

                    List<String> addrParts = cleanAddr.split(',');
                    if (addrParts.size() >= 2) {
                        String city = addrParts[addrParts.size() - 2].trim();
                        if (String.isNotBlank(city)) queriesToTry.add(city + ', India');
                    }
                    // Try 3: state (last segment after PIN removal)
                    String state = addrParts[addrParts.size() - 1].trim();
                    if (String.isNotBlank(state)) queriesToTry.add(state + ', India');
                }
            } else {
                queriesToTry.add(query + ', India');
                if (query.contains(',')) {
                    queriesToTry.add(query.split(',')[0].trim() + ', India');
                }
            }

            // Try each query until one returns results
            for (String q : queriesToTry) {
                String endpoint = NOMINATIM_URL
                    + '?q='          + EncodingUtil.urlEncode(q, 'UTF-8')
                    + '&format=json'
                    + '&limit=1'
                    + '&countrycodes=in';

                HttpRequest req = new HttpRequest();
                req.setEndpoint(endpoint);
                req.setMethod('GET');
                req.setHeader('User-Agent', 'RouteSync-Salesforce/1.0');
                req.setTimeout(10000);

                HttpResponse res = new Http().send(req);
                System.debug('Geocode [' + q + '] HTTP=' + res.getStatusCode());

                if (res.getStatusCode() == 200) {
                    List<Object> geoResults = (List<Object>) JSON.deserializeUntyped(res.getBody());
                    if (!geoResults.isEmpty()) {
                        Map<String, Object> gr = (Map<String, Object>) geoResults[0];
                        LocationResult r = new LocationResult();
                        r.label     = query;
                        r.latitude  = Double.valueOf(String.valueOf(gr.get('lat')));
                        r.longitude = Double.valueOf(String.valueOf(gr.get('lon')));
                        r.placeName = query;
                        System.debug('Geocoded [' + q + '] -> ' + r.latitude + ',' + r.longitude);
                        return r;
                    }
                }
                System.debug('Geocode [' + q + '] returned empty, trying next...');
            }
        } catch (Exception ex) {
            System.debug('geocode failed: ' + ex.getMessage());
        }
        return null;
    }
}