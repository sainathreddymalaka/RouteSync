@isTest
private class MapplsAutosuggestService_Test {

    // ── MOCK INFRASTRUCTURE ───────────────────────────────────────────────────

    private class MockResponse implements HttpCalloutMock {
        private final Integer code;
        private final String  body;
        MockResponse(Integer code, String body) { this.code = code; this.body = body; }
        public HTTPResponse respond(HTTPRequest req) {
            HTTPResponse res = new HTTPResponse();
            res.setStatusCode(code);
            res.setBody(body);
            return res;
        }
    }

    // Routes each callout to a different mock based on a URL substring
    private class RoutingMock implements HttpCalloutMock {
        private final Map<String, HttpCalloutMock> routes = new Map<String, HttpCalloutMock>();
        void add(String urlFragment, HttpCalloutMock mock) { routes.put(urlFragment, mock); }
        public HTTPResponse respond(HTTPRequest req) {
            for (String fragment : routes.keySet()) {
                if (req.getEndpoint().contains(fragment)) return routes.get(fragment).respond(req);
            }
            HTTPResponse r = new HTTPResponse(); r.setStatusCode(404); r.setBody('{}'); return r;
        }
    }

    // ── MOCK PAYLOADS ─────────────────────────────────────────────────────────

    private static final String MAPPLS_ONE_RESULT =
        '{"suggestedLocations":[{"placeName":"Bengaluru","placeAddress":"Karnataka, India","eLoc":"ABCDEF"}]}';

    private static final String MAPPLS_SINGLE_SEGMENT_ADDR =
        '{"suggestedLocations":[{"placeName":"Bengaluru","placeAddress":"Karnataka","eLoc":"ABCDEF"}]}';

    private static final String MAPPLS_NO_PLACENAME =
        '{"suggestedLocations":[{"placeName":"","placeAddress":"Karnataka, India","eLoc":"GHIJKL"}]}';

    private static final String MAPPLS_DUPLICATE_LABELS =
        '{"suggestedLocations":['
        + '{"placeName":"Bengaluru","placeAddress":"Karnataka, India","eLoc":"AA"},'
        + '{"placeName":"Bengaluru","placeAddress":"Karnataka, India","eLoc":"BB"}'
        + ']}';

    private static final String MAPPLS_EMPTY_LIST   = '{"suggestedLocations":[]}';
    private static final String MAPPLS_NULL_KEY      = '{}';

    private static final String NOMINATIM_HIT   = '[{"lat":"12.9716","lon":"77.5946","display_name":"Bengaluru, Karnataka, India"}]';
    private static final String NOMINATIM_EMPTY = '[]';

    // ── search() ─────────────────────────────────────────────────────────────

    @isTest
    static void testSearch_Success() {
        Test.setMock(HttpCalloutMock.class, new MockResponse(200, MAPPLS_ONE_RESULT));

        Test.startTest();
        List<String> labels = MapplsAutosuggestService.search('Bengaluru');
        Test.stopTest();

        System.assertEquals(1, labels.size());
        System.assert(labels[0].contains('Bengaluru'));
    }

    @isTest
    static void testSearch_DeduplicatesLabels() {
        Test.setMock(HttpCalloutMock.class, new MockResponse(200, MAPPLS_DUPLICATE_LABELS));

        Test.startTest();
        List<String> labels = MapplsAutosuggestService.search('Bengaluru');
        Test.stopTest();

        System.assertEquals(1, labels.size(), 'Duplicate labels should be deduplicated');
    }

    @isTest
    static void testSearch_NoSuggestedLocationsKey() {
        Test.setMock(HttpCalloutMock.class, new MockResponse(200, MAPPLS_NULL_KEY));

        Test.startTest();
        List<String> labels = MapplsAutosuggestService.search('xyz');
        Test.stopTest();

        System.assertEquals(0, labels.size());
    }

    @isTest
    static void testSearch_BlankQuery() {
        Boolean thrown = false;
        Test.startTest();
        try {
            MapplsAutosuggestService.search('');
        } catch (AuraHandledException e) {
            thrown = true;
        }
        Test.stopTest();

        System.assert(thrown, 'Blank query should throw AuraHandledException');
    }

    @isTest
    static void testSearch_QueryTooLong() {
        Boolean thrown = false;
        String  longQ  = 'a'.repeat(50);
        Test.startTest();
        try {
            MapplsAutosuggestService.search(longQ);
        } catch (AuraHandledException e) {
            thrown = true;
        }
        Test.stopTest();

        System.assert(thrown, 'Query >45 chars should throw AuraHandledException');
    }

    @isTest
    static void testSearch_ApiError() {
        Test.setMock(HttpCalloutMock.class, new MockResponse(500, 'Internal Server Error'));

        Boolean thrown = false;
        Test.startTest();
        try {
            MapplsAutosuggestService.search('Bengaluru');
        } catch (AuraHandledException e) {
            thrown = true;
        }
        Test.stopTest();

        System.assert(thrown, 'Non-200 response should throw AuraHandledException');
    }

    // ── searchWithCoordinates() ───────────────────────────────────────────────

    @isTest
    static void testSearchWithCoordinates_SuccessWithCoords() {
        RoutingMock mock = new RoutingMock();
        mock.add('search.mappls.com',          new MockResponse(200, MAPPLS_ONE_RESULT));
        mock.add('nominatim.openstreetmap.org', new MockResponse(200, NOMINATIM_HIT));
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        List<MapplsAutosuggestService.LocationResult> results =
            MapplsAutosuggestService.searchWithCoordinates('Bengaluru');
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals('Bengaluru',  results[0].placeName);
        System.assertEquals(12.9716,      results[0].latitude);
        System.assertEquals(77.5946,      results[0].longitude);
        System.assertEquals('Karnataka',  results[0].city);
        System.assertEquals('India',      results[0].state);
    }

    @isTest
    static void testSearchWithCoordinates_SingleSegmentAddress() {
        // Exercises the parts.size() == 1 branch in city/state parsing
        RoutingMock mock = new RoutingMock();
        mock.add('search.mappls.com',          new MockResponse(200, MAPPLS_SINGLE_SEGMENT_ADDR));
        mock.add('nominatim.openstreetmap.org', new MockResponse(200, NOMINATIM_HIT));
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        List<MapplsAutosuggestService.LocationResult> results =
            MapplsAutosuggestService.searchWithCoordinates('Bengaluru');
        Test.stopTest();

        System.assertEquals(1,           results.size());
        System.assertEquals('Karnataka', results[0].city);
        System.assertEquals('',          results[0].state);
    }

    @isTest
    static void testSearchWithCoordinates_NominatimEmpty() {
        // Nominatim returns [] — coordinates should remain null
        RoutingMock mock = new RoutingMock();
        mock.add('search.mappls.com',          new MockResponse(200, MAPPLS_ONE_RESULT));
        mock.add('nominatim.openstreetmap.org', new MockResponse(200, NOMINATIM_EMPTY));
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        List<MapplsAutosuggestService.LocationResult> results =
            MapplsAutosuggestService.searchWithCoordinates('Bengaluru');
        Test.stopTest();

        System.assertEquals(1,    results.size());
        System.assertEquals(null, results[0].latitude,  'No coords when Nominatim is empty');
        System.assertEquals(null, results[0].longitude, 'No coords when Nominatim is empty');
    }

    @isTest
    static void testSearchWithCoordinates_EmptyMapplsResults() {
        Test.setMock(HttpCalloutMock.class, new MockResponse(200, MAPPLS_EMPTY_LIST));

        Test.startTest();
        List<MapplsAutosuggestService.LocationResult> results =
            MapplsAutosuggestService.searchWithCoordinates('xyz');
        Test.stopTest();

        System.assertEquals(0, results.size());
    }

    @isTest
    static void testSearchWithCoordinates_MapplsApiError() {
        Test.setMock(HttpCalloutMock.class, new MockResponse(503, 'Unavailable'));

        Boolean thrown = false;
        Test.startTest();
        try {
            MapplsAutosuggestService.searchWithCoordinates('Bengaluru');
        } catch (AuraHandledException e) {
            thrown = true;
        }
        Test.stopTest();

        System.assert(thrown, 'Mappls 503 should throw AuraHandledException');
    }

    @isTest
    static void testSearchWithCoordinates_BlankQuery() {
        Boolean thrown = false;
        Test.startTest();
        try {
            MapplsAutosuggestService.searchWithCoordinates('');
        } catch (AuraHandledException e) {
            thrown = true;
        }
        Test.stopTest();

        System.assert(thrown, 'Blank query should throw AuraHandledException');
    }

    @isTest
    static void testSearchWithCoordinates_QueryTooLong() {
        Boolean thrown = false;
        Test.startTest();
        try {
            MapplsAutosuggestService.searchWithCoordinates('x'.repeat(50));
        } catch (AuraHandledException e) {
            thrown = true;
        }
        Test.stopTest();

        System.assert(thrown, 'Query >45 chars should throw AuraHandledException');
    }

    // ── geocode() ─────────────────────────────────────────────────────────────

    @isTest
    static void testGeocode_BlankQuery() {
        Test.startTest();
        MapplsAutosuggestService.LocationResult result = MapplsAutosuggestService.geocode('');
        Test.stopTest();

        System.assertEquals(null, result, 'Blank query should return null immediately');
    }

    @isTest
    static void testGeocode_SimpleQuery_Hit() {
        Test.setMock(HttpCalloutMock.class, new MockResponse(200, NOMINATIM_HIT));

        Test.startTest();
        MapplsAutosuggestService.LocationResult result =
            MapplsAutosuggestService.geocode('Bengaluru');
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertEquals(12.9716, result.latitude);
        System.assertEquals(77.5946, result.longitude);
    }

    @isTest
    static void testGeocode_QueryWithComma() {
        // Exercises the query.contains(',') branch — produces a second fallback query
        Test.setMock(HttpCalloutMock.class, new MockResponse(200, NOMINATIM_HIT));

        Test.startTest();
        MapplsAutosuggestService.LocationResult result =
            MapplsAutosuggestService.geocode('Bengaluru, Karnataka');
        Test.stopTest();

        System.assertNotEquals(null, result);
    }

    @isTest
    static void testGeocode_EmdashFormat_MultiPart() {
        // Exercises the em-dash (–) branch with PIN code removal
        // Format: "Place – Address, City, State, 560001"
        Test.setMock(HttpCalloutMock.class, new MockResponse(200, NOMINATIM_HIT));
        String query = 'MG Road – Bengaluru, Karnataka, 560001';

        Test.startTest();
        MapplsAutosuggestService.LocationResult result = MapplsAutosuggestService.geocode(query);
        Test.stopTest();

        System.assertNotEquals(null, result);
    }

    @isTest
    static void testGeocode_EmdashFormat_SinglePartAddress() {
        // Exercises the addrParts.size() < 2 branch inside the em-dash path
        Test.setMock(HttpCalloutMock.class, new MockResponse(200, NOMINATIM_HIT));
        String query = 'Some Place – Karnataka';

        Test.startTest();
        MapplsAutosuggestService.LocationResult result = MapplsAutosuggestService.geocode(query);
        Test.stopTest();

        System.assertNotEquals(null, result);
    }

    @isTest
    static void testGeocode_EmptyNominatimResult() {
        // All queries return empty array — geocode should return null
        Test.setMock(HttpCalloutMock.class, new MockResponse(200, NOMINATIM_EMPTY));

        Test.startTest();
        MapplsAutosuggestService.LocationResult result =
            MapplsAutosuggestService.geocode('NowhereSpecial');
        Test.stopTest();

        System.assertEquals(null, result, 'Should return null when Nominatim finds nothing');
    }
}
