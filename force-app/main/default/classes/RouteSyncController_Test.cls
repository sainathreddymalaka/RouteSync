@isTest
private class RouteSyncController_Test {

    // ── SETUP ────────────────────────────────────────────────────────────────

    @TestSetup
    static void setupData() {
        Account driver = new Account(
            Name        = 'Test Driver',
            Email__c    = 'driver@test.com',
            Phone       = '9876543210',
            Password__c = sha256('password123'),
            Gender__c   = 'Male',
            Type        = 'Person Account'
        );
        insert driver;

        Account passenger = new Account(
            Name        = 'Test Passenger',
            Email__c    = 'passenger@test.com',
            Phone       = '9876543211',
            Password__c = sha256('password123'),
            Gender__c   = 'Female',
            Type        = 'Person Account'
        );
        insert passenger;

        // Bengaluru → Hyderabad ride with geo coordinates
        insert new Ride__c(
            Publisher__c          = driver.Id,
            From_Location__c      = 'Bengaluru',
            To_Location__c        = 'Hyderabad',
            Departure_DateTime__c = DateTime.newInstance(Date.today().addDays(1), Time.newInstance(9, 0, 0, 0)),
            Available_Seats__c    = 3,
            Price_Per_Seat__c     = 500,
            Vehicle_Type__c       = 'Car',
            Notes__c              = 'Test ride',
            Status__c             = 'Active',
            From_Latitude__c      = 12.9716,
            From_Longitude__c     = 77.5946,
            To_Latitude__c        = 17.3850,
            To_Longitude__c       = 78.4867,
            From_City__c          = 'Bengaluru',
            From_State__c         = 'Karnataka',
            To_City__c            = 'Hyderabad',
            To_State__c           = 'Telangana'
        );
    }

    private static String sha256(String plainText) {
        return EncodingUtil.base64Encode(Crypto.generateDigest('SHA-256', Blob.valueOf(plainText)));
    }

    private static Account getDriver()    { return [SELECT Id FROM Account WHERE Email__c = 'driver@test.com'    LIMIT 1]; }
    private static Account getPassenger() { return [SELECT Id FROM Account WHERE Email__c = 'passenger@test.com' LIMIT 1]; }
    private static Ride__c  getRide()     { return [SELECT Id, Available_Seats__c FROM Ride__c LIMIT 1]; }

    // ── REGISTER ─────────────────────────────────────────────────────────────

    @isTest
    static void testRegisterUser_Success() {
        Test.startTest();
        Map<String, Object> result = RouteSyncController.registerUser(
            'New User', 'newuser@test.com', '9000000099', 'Password1',
            Date.today().addYears(-25), 'Male'
        );
        Test.stopTest();

        System.assertEquals(true, result.get('success'));
        System.assertNotEquals(null, result.get('userId'));
    }

    @isTest
    static void testRegisterUser_DuplicateEmail() {
        Test.startTest();
        Map<String, Object> result = RouteSyncController.registerUser(
            'Dup', 'driver@test.com', '9000000099', 'Pass',
            Date.today().addYears(-20), 'Male'
        );
        Test.stopTest();

        System.assertEquals(false, result.get('success'));
        System.assert(((String) result.get('message')).contains('already registered'));
    }

    // ── LOGIN ────────────────────────────────────────────────────────────────

    @isTest
    static void testLoginUser_Success() {
        Test.startTest();
        Map<String, Object> result = RouteSyncController.loginUser('driver@test.com', 'password123');
        Test.stopTest();

        System.assertEquals(true,  result.get('success'));
        System.assertEquals('Login successful!', result.get('message'));
    }

    @isTest
    static void testLoginUser_WrongPassword() {
        Test.startTest();
        Map<String, Object> result = RouteSyncController.loginUser('driver@test.com', 'wrongpass');
        Test.stopTest();

        System.assertEquals(false, result.get('success'));
    }

    @isTest
    static void testLoginUser_UnknownEmail() {
        Test.startTest();
        Map<String, Object> result = RouteSyncController.loginUser('nobody@test.com', 'pass');
        Test.stopTest();

        System.assertEquals(false, result.get('success'));
    }

    // ── PUBLISH RIDE ─────────────────────────────────────────────────────────

    @isTest
    static void testPublishRide_Success() {
        Id driverId = getDriver().Id;

        Test.startTest();
        Map<String, Object> result = RouteSyncController.publishRide(
            driverId, 'Chennai', 'Bengaluru',
            DateTime.now().addDays(2), 2, 300, 'Car', 'AC available',
            null, 13.0827, 80.2707, 'Chennai', 'Tamil Nadu',
            null, 12.9716, 77.5946, 'Bengaluru', 'Karnataka'
        );
        Test.stopTest();

        System.assertEquals(true, result.get('success'));
        System.assertNotEquals(null, result.get('rideId'));
    }

    // ── SEARCH RIDES ─────────────────────────────────────────────────────────

    @isTest
    static void testSearchRides_GeoPath() {
        Date tomorrow = Date.today().addDays(1);

        Test.startTest();
        List<Ride__c> results = RouteSyncController.searchRides(
            'Bengaluru', 'Hyderabad', tomorrow, 1,
            12.9716, 77.5946,   // exact match — fromDist = 0
            17.3850, 78.4867,   // exact match — toDist  = 0
            30
        );
        Test.stopTest();

        System.assert(!results.isEmpty(), 'Geo search should return the test ride');
    }

    @isTest
    static void testSearchRides_LikeFallback() {
        // Passing null coords triggers auto-geocode → CalloutException caught → LIKE fallback
        Date tomorrow = Date.today().addDays(1);

        Test.startTest();
        List<Ride__c> results = RouteSyncController.searchRides(
            'Bengaluru', 'Hyderabad', tomorrow, 1,
            null, null, null, null, null
        );
        Test.stopTest();

        System.assert(!results.isEmpty(), 'LIKE fallback should find the test ride');
    }

    @isTest
    static void testSearchRides_NoMatch() {
        Date tomorrow = Date.today().addDays(1);

        Test.startTest();
        List<Ride__c> results = RouteSyncController.searchRides(
            'Mumbai', 'Pune', tomorrow, 1, null, null, null, null, null
        );
        Test.stopTest();

        System.assertEquals(0, results.size());
    }

    // ── BOOK RIDE ────────────────────────────────────────────────────────────

    @isTest
    static void testBookRide_Success() {
        Id passengerId = getPassenger().Id;
        Id rideId      = getRide().Id;

        Test.startTest();
        Map<String, Object> result = RouteSyncController.bookRide(rideId, passengerId, 1);
        Test.stopTest();

        System.assertEquals(true, result.get('success'));
        System.assertNotEquals(null, result.get('bookingId'));
        System.assertEquals(2, Integer.valueOf(
            [SELECT Available_Seats__c FROM Ride__c WHERE Id = :rideId].Available_Seats__c
        ));
    }

    @isTest
    static void testBookRide_SelfBooking() {
        Id driverId = getDriver().Id;
        Id rideId   = getRide().Id;

        Test.startTest();
        Map<String, Object> result = RouteSyncController.bookRide(rideId, driverId, 1);
        Test.stopTest();

        System.assertEquals(false, result.get('success'));
        System.assertEquals('You cannot book your own ride.', result.get('message'));
    }

    @isTest
    static void testBookRide_DuplicateBooking() {
        Id passengerId = getPassenger().Id;
        Id rideId      = getRide().Id;
        RouteSyncController.bookRide(rideId, passengerId, 1);  // first booking

        Test.startTest();
        Map<String, Object> result = RouteSyncController.bookRide(rideId, passengerId, 1);
        Test.stopTest();

        System.assertEquals(false, result.get('success'));
        System.assertEquals('You have already booked this ride.', result.get('message'));
    }

    @isTest
    static void testBookRide_NotEnoughSeats() {
        Id passengerId = getPassenger().Id;
        Id rideId      = getRide().Id;

        Test.startTest();
        Map<String, Object> result = RouteSyncController.bookRide(rideId, passengerId, 99);
        Test.stopTest();

        System.assertEquals(false, result.get('success'));
        System.assertEquals('Not enough seats available.', result.get('message'));
    }

    // ── USER DATA ────────────────────────────────────────────────────────────

    @isTest
    static void testGetUserBookings() {
        Id passengerId = getPassenger().Id;
        Id rideId      = getRide().Id;
        insert new Booking__c(
            Ride__c = rideId, Passenger__c = passengerId,
            Seats_Booked__c = 1, Status__c = 'Confirmed',
            Booking_DateTime__c = System.now()
        );

        Test.startTest();
        List<Booking__c> bookings = RouteSyncController.getUserBookings(passengerId);
        Test.stopTest();

        System.assertEquals(1, bookings.size());
    }

    @isTest
    static void testGetUserPublishedRides() {
        Id driverId = getDriver().Id;

        Test.startTest();
        List<Ride__c> rides = RouteSyncController.getUserPublishedRides(driverId);
        Test.stopTest();

        System.assertEquals(1, rides.size());
    }

    @isTest
    static void testGetUserLocationHistory_FromPublishedRides() {
        Id driverId = getDriver().Id;

        Test.startTest();
        Map<String, Object> result = RouteSyncController.getUserLocationHistory(driverId);
        Test.stopTest();

        System.assertEquals(true, result.get('success'));
        List<String> fromLocs = (List<String>) result.get('fromLocations');
        System.assert(!fromLocs.isEmpty(), 'Should include Bengaluru from test ride');
    }

    @isTest
    static void testGetUserLocationHistory_FromBookings() {
        // Cover the booking loop inside getUserLocationHistory
        Id passengerId = getPassenger().Id;
        Id rideId      = getRide().Id;
        insert new Booking__c(
            Ride__c = rideId, Passenger__c = passengerId,
            Seats_Booked__c = 1, Status__c = 'Confirmed',
            Booking_DateTime__c = System.now()
        );

        Test.startTest();
        Map<String, Object> result = RouteSyncController.getUserLocationHistory(passengerId);
        Test.stopTest();

        System.assertEquals(true, result.get('success'));
        List<String> fromLocs = (List<String>) result.get('fromLocations');
        System.assert(!fromLocs.isEmpty(), 'Should include locations from booked rides');
    }

    // ── MODAL DETAIL QUERIES ─────────────────────────────────────────────────

    @isTest
    static void testGetBookingDetails() {
        Id passengerId = getPassenger().Id;
        Id rideId      = getRide().Id;
        Booking__c booking = new Booking__c(
            Ride__c = rideId, Passenger__c = passengerId,
            Seats_Booked__c = 1, Status__c = 'Confirmed',
            Booking_DateTime__c = System.now()
        );
        insert booking;

        Test.startTest();
        Booking__c result = RouteSyncController.getBookingDetails(booking.Id);
        Test.stopTest();

        System.assertEquals(booking.Id, result.Id);
    }

    @isTest
    static void testGetRideDetails() {
        Id rideId = getRide().Id;

        Test.startTest();
        Ride__c result = RouteSyncController.getRideDetails(rideId);
        Test.stopTest();

        System.assertEquals(rideId, result.Id);
    }

    // ── UPDATE BOOKING ────────────────────────────────────────────────────────

    @isTest
    static void testUpdateBooking_IncreaseSeats() {
        Id passengerId = getPassenger().Id;
        Id rideId      = getRide().Id;
        Booking__c booking = new Booking__c(
            Ride__c = rideId, Passenger__c = passengerId,
            Seats_Booked__c = 1, Status__c = 'Confirmed',
            Booking_DateTime__c = System.now()
        );
        insert booking;

        Test.startTest();
        Map<String, Object> result = RouteSyncController.updateBooking(booking.Id, 2);
        Test.stopTest();

        System.assertEquals(true, result.get('success'));
        System.assertEquals(2, Integer.valueOf(
            [SELECT Seats_Booked__c FROM Booking__c WHERE Id = :booking.Id].Seats_Booked__c
        ));
    }

    @isTest
    static void testUpdateBooking_DecreaseSeats() {
        Id passengerId = getPassenger().Id;
        Id rideId      = getRide().Id;
        Booking__c booking = new Booking__c(
            Ride__c = rideId, Passenger__c = passengerId,
            Seats_Booked__c = 2, Status__c = 'Confirmed',
            Booking_DateTime__c = System.now()
        );
        insert booking;

        Test.startTest();
        Map<String, Object> result = RouteSyncController.updateBooking(booking.Id, 1);
        Test.stopTest();

        System.assertEquals(true, result.get('success'));
    }

    @isTest
    static void testUpdateBooking_NotEnoughSeats() {
        Id passengerId = getPassenger().Id;
        Id rideId      = getRide().Id;
        Booking__c booking = new Booking__c(
            Ride__c = rideId, Passenger__c = passengerId,
            Seats_Booked__c = 1, Status__c = 'Confirmed',
            Booking_DateTime__c = System.now()
        );
        insert booking;
        // Ride has 3 available; asking for 99 total → difference = 98 > available
        Test.startTest();
        Map<String, Object> result = RouteSyncController.updateBooking(booking.Id, 99);
        Test.stopTest();

        System.assertEquals(false, result.get('success'));
    }

    // ── CANCEL BOOKING ────────────────────────────────────────────────────────

    @isTest
    static void testCancelBooking() {
        Id passengerId = getPassenger().Id;
        Ride__c ride   = getRide();
        Booking__c booking = new Booking__c(
            Ride__c = ride.Id, Passenger__c = passengerId,
            Seats_Booked__c = 2, Status__c = 'Confirmed',
            Booking_DateTime__c = System.now()
        );
        insert booking;
        // Manually deduct seats to simulate what bookRide does
        ride.Available_Seats__c -= 2;
        update ride;

        Test.startTest();
        Map<String, Object> result = RouteSyncController.cancelBooking(booking.Id);
        Test.stopTest();

        System.assertEquals(true, result.get('success'));
        // Seats should be restored to 3
        System.assertEquals(3, Integer.valueOf(
            [SELECT Available_Seats__c FROM Ride__c WHERE Id = :ride.Id].Available_Seats__c
        ));
    }

    // ── UPDATE RIDE ───────────────────────────────────────────────────────────

    @isTest
    static void testUpdateRide() {
        Id rideId = getRide().Id;

        Test.startTest();
        Map<String, Object> result = RouteSyncController.updateRide(
            rideId, DateTime.now().addDays(3), 4, 600, 'SUV', 'Updated notes'
        );
        Test.stopTest();

        System.assertEquals(true, result.get('success'));
        Ride__c updated = [SELECT Available_Seats__c, Price_Per_Seat__c FROM Ride__c WHERE Id = :rideId];
        System.assertEquals(4,   Integer.valueOf(updated.Available_Seats__c));
        System.assertEquals(600, Integer.valueOf(updated.Price_Per_Seat__c));
    }

    // ── DELETE RIDE ───────────────────────────────────────────────────────────

    @isTest
    static void testDeleteRide_NoBookings() {
        Id driverId = getDriver().Id;
        Ride__c extra = new Ride__c(
            Publisher__c = driverId, From_Location__c = 'Delhi',
            To_Location__c = 'Agra',
            Departure_DateTime__c = DateTime.now().addDays(5),
            Available_Seats__c = 2, Price_Per_Seat__c = 200,
            Vehicle_Type__c = 'Car', Status__c = 'Active'
        );
        insert extra;

        Test.startTest();
        Map<String, Object> result = RouteSyncController.deleteRide(extra.Id);
        Test.stopTest();

        System.assertEquals(true, result.get('success'));
        System.assertEquals(0, [SELECT COUNT() FROM Ride__c WHERE Id = :extra.Id]);
    }

    @isTest
    static void testDeleteRide_HasConfirmedBookings() {
        Id passengerId = getPassenger().Id;
        Id rideId      = getRide().Id;
        insert new Booking__c(
            Ride__c = rideId, Passenger__c = passengerId,
            Seats_Booked__c = 1, Status__c = 'Confirmed',
            Booking_DateTime__c = System.now()
        );

        Test.startTest();
        Map<String, Object> result = RouteSyncController.deleteRide(rideId);
        Test.stopTest();

        System.assertEquals(false, result.get('success'));
        System.assert(((String) result.get('message')).contains('Cannot delete'));
    }

    // ── PROFILE PICTURE ───────────────────────────────────────────────────────

    @isTest
    static void testUploadAndGetProfilePicture() {
        Id driverId = getDriver().Id;
        String b64  = EncodingUtil.base64Encode(Blob.valueOf('fake-image-bytes'));

        Test.startTest();
        Map<String, Object> uploadResult = RouteSyncController.uploadProfilePicture(
            driverId, 'profile.jpg', b64, 'image/jpeg'
        );
        Map<String, Object> getResult = RouteSyncController.getProfilePictureNonCacheable(driverId);
        Test.stopTest();

        System.assertEquals(true, uploadResult.get('success'), 'Upload should succeed');
        System.assertEquals(true, getResult.get('success'),    'Get should succeed after upload');
        System.assertNotEquals(null, getResult.get('pictureUrl'));
    }

    @isTest
    static void testUploadProfilePicture_ReplacesExisting() {
        Id driverId = getDriver().Id;
        String b64  = EncodingUtil.base64Encode(Blob.valueOf('image-data'));

        // First upload — creates the initial picture
        RouteSyncController.uploadProfilePicture(driverId, 'v1.jpg', b64, 'image/jpeg');

        Test.startTest();
        // Second upload — should delete old and create new
        Map<String, Object> result = RouteSyncController.uploadProfilePicture(driverId, 'v2.jpg', b64, 'image/jpeg');
        Test.stopTest();

        System.assertEquals(true, result.get('success'));
        System.assertEquals(1, [
            SELECT COUNT() FROM ContentDocumentLink
            WHERE LinkedEntityId = :driverId
            AND ContentDocument.Title = 'ProfilePicture'
        ]);
    }

    @isTest
    static void testGetProfilePicture_NoPicture() {
        Id passengerId = getPassenger().Id;

        Test.startTest();
        Map<String, Object> result = RouteSyncController.getProfilePictureNonCacheable(passengerId);
        Test.stopTest();

        System.assertEquals(false, result.get('success'));
        System.assertEquals(null,  result.get('pictureUrl'));
    }

    @isTest
    static void testDeleteProfilePicture_Success() {
        Id driverId = getDriver().Id;
        String b64  = EncodingUtil.base64Encode(Blob.valueOf('image-data'));
        RouteSyncController.uploadProfilePicture(driverId, 'profile.jpg', b64, 'image/jpeg');

        Test.startTest();
        Map<String, Object> result = RouteSyncController.deleteProfilePicture(driverId);
        Test.stopTest();

        System.assertEquals(true, result.get('success'));
        System.assertEquals(0, [
            SELECT COUNT() FROM ContentDocumentLink
            WHERE LinkedEntityId = :driverId
            AND ContentDocument.Title = 'ProfilePicture'
        ]);
    }

    @isTest
    static void testDeleteProfilePicture_NoPicture() {
        Id passengerId = getPassenger().Id;

        Test.startTest();
        Map<String, Object> result = RouteSyncController.deleteProfilePicture(passengerId);
        Test.stopTest();

        System.assertEquals(false, result.get('success'));
        System.assertEquals('No profile picture found to delete', result.get('message'));
    }

    // ── PASSWORD MIGRATION ────────────────────────────────────────────────────

    @isTest
    static void testMigratePasswords_MigratesPlainText() {
        // Insert account whose password is shorter than 44 chars (plain text)
        insert new Account(
            Name = 'Plain User', Email__c = 'plain@test.com',
            Phone = '9000000001', Password__c = 'plain123', Type = 'Person Account'
        );

        Test.startTest();
        Map<String, Object> result = RouteSyncController.migratePasswordsToHash();
        Test.stopTest();

        System.assertEquals(true, result.get('success'));
        System.assertEquals(44, [SELECT Password__c FROM Account WHERE Email__c = 'plain@test.com'].Password__c.length());
    }

    @isTest
    static void testMigratePasswords_SkipsAlreadyHashed() {
        // @TestSetup accounts already have 44-char SHA-256 hashes — should be skipped
        Test.startTest();
        Map<String, Object> result = RouteSyncController.migratePasswordsToHash();
        Test.stopTest();

        System.assertEquals(true, result.get('success'));
        System.assert(((String) result.get('message')).contains('Migrated 0'));
    }
}
