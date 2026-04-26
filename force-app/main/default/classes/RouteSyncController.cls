/**
* @File Name : RouteSyncController.cls
* @Description : Complete controller with all CRUD and profile picture methods
* @Modification Log :
*==============================================================================
* Ver | Date       | Modification
*==============================================================================
* 1.0 | Sep 2025   | Initial Version
* 2.0 | Oct 2025   | Added getUserLocationHistory method
* 3.0 | Oct 2025   | Added modal CRUD methods
* 4.0 | Nov 2025   | Added profile picture with delete
* 5.0 | Apr 2026   | SECURITY: SHA-256 password hashing
*                  | BUG FIX: Self-booking prevention
*                  | BUG FIX: Duplicate booking check
*                  | BUG FIX: updateBooking no longer changes ride departure time
*                  | CLEANUP: Removed cacheable from getUserPublishedRides
*                  | CLEANUP: Removed duplicate refreshUserPublishedRides
*==============================================================================
**/

public without sharing class RouteSyncController {

    // ─── UTILITY ────────────────────────────────────────────────────────────

    /**
     * Hash a plain-text password using SHA-256.
     * Used for both registration and login comparison.
     */
    private static String hashPassword(String plainText) {
        Blob hash = Crypto.generateDigest('SHA-256', Blob.valueOf(plainText));
        return EncodingUtil.base64Encode(hash);
    }

    // ─── AUTH ────────────────────────────────────────────────────────────────

    @AuraEnabled
    public static Map<String, Object> registerUser(String name, String email, String phone,
                                                   String password, Date dateOfBirth, String gender) {
        try {
            // Check for duplicate email
            List<Account> existingAccounts = [SELECT Id FROM Account WHERE Email__c = :email LIMIT 1];
            if (!existingAccounts.isEmpty()) {
                return new Map<String, Object>{
                    'success' => false,
                    'message' => 'Email already registered. Please use a different email.'
                };
            }

            // Hash password before storing — never store plain text
            String hashedPassword = hashPassword(password);

            Account newUser = new Account(
                Name         = name,
                Email__c     = email,
                Phone        = phone,
                Password__c  = hashedPassword,
                Date_of_Birth__c = dateOfBirth,
                Gender__c    = gender,
                Type         = 'Person Account'
            );

            insert newUser;

            return new Map<String, Object>{
                'success' => true,
                'message' => 'Registration successful!',
                'userId'  => newUser.Id
            };

        } catch (Exception e) {
            return new Map<String, Object>{
                'success' => false,
                'message' => 'Registration failed: ' + e.getMessage()
            };
        }
    }

    @AuraEnabled
    public static Map<String, Object> loginUser(String email, String password) {
        try {
            // Hash the input password and compare against stored hash
            String hashedPassword = hashPassword(password);

            List<Account> users = [
                SELECT Id, Name, Email__c, Phone
                FROM Account
                WHERE Email__c = :email
                AND Password__c = :hashedPassword
                LIMIT 1
            ];

            if (users.isEmpty()) {
                return new Map<String, Object>{
                    'success' => false,
                    'message' => 'Invalid email or password'
                };
            }

            Account user = users[0];
            return new Map<String, Object>{
                'success' => true,
                'message' => 'Login successful!',
                'user'    => user
            };

        } catch (Exception e) {
            return new Map<String, Object>{
                'success' => false,
                'message' => 'Login failed: ' + e.getMessage()
            };
        }
    }

    // ─── RIDE PUBLISH & SEARCH ───────────────────────────────────────────────

    @AuraEnabled
    public static Map<String, Object> publishRide(
            String userId, String fromLocation, String toLocation,
            DateTime departureDateTime, Integer availableSeats,
            Decimal pricePerSeat, String vehicleType, String notes,
            // Geo fields — optional, sent when user picks from Mappls autocomplete
            String fromELoc, Decimal fromLat, Decimal fromLng, String fromCity, String fromState,
            String toELoc,   Decimal toLat,   Decimal toLng,   String toCity,   String toState) {
        try {
            Ride__c newRide = new Ride__c(
                Publisher__c          = userId,
                From_Location__c      = fromLocation,
                To_Location__c        = toLocation,
                Departure_DateTime__c = departureDateTime,
                Available_Seats__c    = availableSeats,
                Price_Per_Seat__c     = pricePerSeat,
                Vehicle_Type__c       = vehicleType,
                Notes__c              = notes,
                Status__c             = 'Active',
                // Geo fields
                From_eLoc__c          = fromELoc,
                From_Latitude__c      = fromLat,
                From_Longitude__c     = fromLng,
                From_City__c          = fromCity,
                From_State__c         = fromState,
                To_eLoc__c            = toELoc,
                To_Latitude__c        = toLat,
                To_Longitude__c       = toLng,
                To_City__c            = toCity,
                To_State__c           = toState
            );

            insert newRide;

            return new Map<String, Object>{
                'success' => true,
                'message' => 'Ride published successfully!',
                'rideId'  => newRide.Id
            };

        } catch (Exception e) {
            return new Map<String, Object>{
                'success' => false,
                'message' => 'Failed to publish ride: ' + e.getMessage()
            };
        }
    }

    // ─── SEARCH WITH PROXIMITY ────────────────────────────────────────────────

    // Haversine formula — returns distance in KM between two lat/lng points
    // All params are Double — callers must cast Decimal fields with .doubleValue()
    private static Double haversineKm(Double lat1, Double lng1, Double lat2, Double lng2) {
        final Double R  = 6371.0; // Earth radius in KM
        final Double PI = 3.14159265358979323846;

        Double dLat = (lat2 - lat1) * PI / 180.0;
        Double dLng = (lng2 - lng1) * PI / 180.0;
        Double rLat1 = lat1 * PI / 180.0;
        Double rLat2 = lat2 * PI / 180.0;

        Double a = Math.sin(dLat / 2) * Math.sin(dLat / 2)
                 + Math.cos(rLat1) * Math.cos(rLat2)
                 * Math.sin(dLng / 2) * Math.sin(dLng / 2);
        Double c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
        return R * c;
    }

    @AuraEnabled
    public static List<Ride__c> searchRides(
            String fromLocation, String toLocation,
            Date travelDate, Integer passengers,
            Decimal fromLat, Decimal fromLng,
            Decimal toLat,   Decimal toLng,
            Decimal radiusKm) {
        try {
            DateTime startOfDay = DateTime.newInstance(travelDate, Time.newInstance(0, 0, 0, 0));
            DateTime endOfDay   = DateTime.newInstance(travelDate, Time.newInstance(23, 59, 59, 999));
            Double   radius     = radiusKm != null ? (Double) radiusKm : 30.0;

            // ── AUTO-GEOCODE if coordinates not provided by LWC ──────────────
            // This makes search work correctly even if JS geo capture fails
            if (fromLat == null || fromLng == null) {
                try {
                    MapplsAutosuggestService.LocationResult fromGeo =
                        MapplsAutosuggestService.geocode(fromLocation);
                    if (fromGeo != null && fromGeo.latitude != null) {
                        fromLat = fromGeo.latitude;
                        fromLng = fromGeo.longitude;
                        System.debug('Auto-geocoded FROM: ' + fromLocation + ' → ' + fromLat + ',' + fromLng);
                    }
                } catch (Exception ex) {
                    System.debug('Auto-geocode FROM failed: ' + ex.getMessage());
                }
            }

            if (toLat == null || toLng == null) {
                try {
                    MapplsAutosuggestService.LocationResult toGeo =
                        MapplsAutosuggestService.geocode(toLocation);
                    if (toGeo != null && toGeo.latitude != null) {
                        toLat = toGeo.latitude;
                        toLng = toGeo.longitude;
                        System.debug('Auto-geocoded TO: ' + toLocation + ' → ' + toLat + ',' + toLng);
                    }
                } catch (Exception ex) {
                    System.debug('Auto-geocode TO failed: ' + ex.getMessage());
                }
            }
            if (fromLat != null && fromLng != null && toLat != null && toLng != null) {

                // Bounding box pre-filter (1 degree ≈ 111 km — faster than checking all records)
                Double latDelta = radius / 111.0;
                Double lngDelta = radius / (111.0 * Math.cos((Double) fromLat * 3.14159265358979 / 180.0));

                Double fromLatMin = (Double) fromLat - latDelta;
                Double fromLatMax = (Double) fromLat + latDelta;
                Double fromLngMin = (Double) fromLng - lngDelta;
                Double fromLngMax = (Double) fromLng + lngDelta;

                Double toLatDelta = radius / 111.0;
                Double toLngDelta = radius / (111.0 * Math.cos((Double) toLat * 3.14159265358979 / 180.0));

                Double toLatMin = (Double) toLat - toLatDelta;
                Double toLatMax = (Double) toLat + toLatDelta;
                Double toLngMin = (Double) toLng - toLngDelta;
                Double toLngMax = (Double) toLng + toLngDelta;

                // Fetch candidates within bounding box
                List<Ride__c> candidates = [
                    SELECT Id, Publisher__r.Name, Publisher__r.Id, Publisher__r.Phone,
                           From_Location__c, To_Location__c,
                           From_Latitude__c, From_Longitude__c,
                           To_Latitude__c, To_Longitude__c,
                           Departure_DateTime__c, Available_Seats__c,
                           Price_Per_Seat__c, Vehicle_Type__c, Notes__c
                    FROM Ride__c
                    WHERE Departure_DateTime__c >= :startOfDay
                    AND   Departure_DateTime__c <= :endOfDay
                    AND   Available_Seats__c    >= :passengers
                    AND   Status__c = 'Active'
                    AND   From_Latitude__c      >= :fromLatMin
                    AND   From_Latitude__c      <= :fromLatMax
                    AND   From_Longitude__c     >= :fromLngMin
                    AND   From_Longitude__c     <= :fromLngMax
                    AND   To_Latitude__c        >= :toLatMin
                    AND   To_Latitude__c        <= :toLatMax
                    AND   To_Longitude__c       >= :toLngMin
                    AND   To_Longitude__c       <= :toLngMax
                    ORDER BY Departure_DateTime__c ASC
                    LIMIT 100
                ];

                // Precise Haversine filter within bounding box results
                List<Ride__c> geoResults = new List<Ride__c>();
                for (Ride__c r : candidates) {
                    if (r.From_Latitude__c == null || r.From_Longitude__c == null
                        || r.To_Latitude__c == null || r.To_Longitude__c == null) continue;

                    Double fromDist = haversineKm(
                        (Double) fromLat, (Double) fromLng,
                        r.From_Latitude__c.doubleValue(), r.From_Longitude__c.doubleValue()
                    );
                    Double toDist = haversineKm(
                        (Double) toLat, (Double) toLng,
                        r.To_Latitude__c.doubleValue(), r.To_Longitude__c.doubleValue()
                    );

                    if (fromDist <= radius && toDist <= radius) {
                        geoResults.add(r);
                    }
                }

                // If geo search found results — return them
                if (!geoResults.isEmpty()) {
                    return geoResults;
                }

                // Geo search found nothing — fall through to LIKE search below
            }

            // ── STRATEGY 2: LIKE text search (fallback) ──────────────────────
            // Used when no coordinates, or geo search returned 0 results
            return [
                SELECT Id, Publisher__r.Name, Publisher__r.Id, Publisher__r.Phone,
                       From_Location__c, To_Location__c,
                       From_Latitude__c, From_Longitude__c,
                       To_Latitude__c, To_Longitude__c,
                       Departure_DateTime__c, Available_Seats__c,
                       Price_Per_Seat__c, Vehicle_Type__c, Notes__c
                FROM Ride__c
                WHERE From_Location__c LIKE :('%' + fromLocation + '%')
                AND   To_Location__c   LIKE :('%' + toLocation   + '%')
                AND   Departure_DateTime__c >= :startOfDay
                AND   Departure_DateTime__c <= :endOfDay
                AND   Available_Seats__c    >= :passengers
                AND   Status__c = 'Active'
                ORDER BY Departure_DateTime__c ASC
                LIMIT 50
            ];

        } catch (Exception e) {
            throw new AuraHandledException('Failed to search rides: ' + e.getMessage());
        }
    }

    // ─── BOOKING ─────────────────────────────────────────────────────────────

    @AuraEnabled
    public static Map<String, Object> bookRide(String rideId, String passengerId, Integer seatsBooked) {
        try {
            Ride__c ride = [
                SELECT Id, Available_Seats__c, Publisher__c
                FROM Ride__c
                WHERE Id = :rideId
                LIMIT 1
            ];

            // Prevent publisher from booking their own ride
            if (ride.Publisher__c == passengerId) {
                return new Map<String, Object>{
                    'success' => false,
                    'message' => 'You cannot book your own ride.'
                };
            }

            // Prevent duplicate booking
            List<Booking__c> existingBookings = [
                SELECT Id FROM Booking__c
                WHERE Ride__c     = :rideId
                AND   Passenger__c = :passengerId
                AND   Status__c   = 'Confirmed'
                LIMIT 1
            ];
            if (!existingBookings.isEmpty()) {
                return new Map<String, Object>{
                    'success' => false,
                    'message' => 'You have already booked this ride.'
                };
            }

            // Check seat availability
            if (ride.Available_Seats__c < seatsBooked) {
                return new Map<String, Object>{
                    'success' => false,
                    'message' => 'Not enough seats available.'
                };
            }

            Booking__c newBooking = new Booking__c(
                Ride__c           = rideId,
                Passenger__c      = passengerId,
                Seats_Booked__c   = seatsBooked,
                Status__c         = 'Confirmed',
                Booking_DateTime__c = System.now()
            );
            insert newBooking;

            ride.Available_Seats__c -= seatsBooked;
            update ride;

            return new Map<String, Object>{
                'success'   => true,
                'message'   => 'Ride booked successfully!',
                'bookingId' => newBooking.Id
            };

        } catch (Exception e) {
            return new Map<String, Object>{
                'success' => false,
                'message' => 'Failed to book ride: ' + e.getMessage()
            };
        }
    }

    // ─── USER DATA ───────────────────────────────────────────────────────────

    @AuraEnabled
    public static List<Booking__c> getUserBookings(String userId) {
        return [
            SELECT Id, Ride__r.From_Location__c, Ride__r.To_Location__c,
                   Ride__r.Departure_DateTime__c, Seats_Booked__c, Status__c,
                   Ride__r.Publisher__r.Name, Ride__r.Publisher__r.Phone,
                   Booking_DateTime__c, Ride__r.Vehicle_Type__c
            FROM Booking__c
            WHERE Passenger__c = :userId
            ORDER BY CreatedDate DESC
            LIMIT 100
        ];
    }

    @AuraEnabled
    public static List<Ride__c> getUserPublishedRides(String userId) {
        return [
            SELECT Id, From_Location__c, To_Location__c, Departure_DateTime__c,
                   Available_Seats__c, Price_Per_Seat__c, Status__c,
                   Vehicle_Type__c, Notes__c,
                   (SELECT Id, Passenger__r.Name, Seats_Booked__c FROM Bookings__r)
            FROM Ride__c
            WHERE Publisher__c = :userId
            ORDER BY CreatedDate DESC
            LIMIT 100
        ];
    }

    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getUserLocationHistory(String userId) {
        try {
            Set<String> fromLocations = new Set<String>();
            Set<String> toLocations   = new Set<String>();

            List<Ride__c> publishedRides = [
                SELECT From_Location__c, To_Location__c
                FROM Ride__c
                WHERE Publisher__c = :userId
                ORDER BY CreatedDate DESC
                LIMIT 50
            ];
            for (Ride__c ride : publishedRides) {
                if (String.isNotBlank(ride.From_Location__c)) fromLocations.add(ride.From_Location__c);
                if (String.isNotBlank(ride.To_Location__c))   toLocations.add(ride.To_Location__c);
            }

            List<Booking__c> bookings = [
                SELECT Ride__r.From_Location__c, Ride__r.To_Location__c
                FROM Booking__c
                WHERE Passenger__c = :userId
                ORDER BY CreatedDate DESC
                LIMIT 50
            ];
            for (Booking__c b : bookings) {
                if (String.isNotBlank(b.Ride__r.From_Location__c)) fromLocations.add(b.Ride__r.From_Location__c);
                if (String.isNotBlank(b.Ride__r.To_Location__c))   toLocations.add(b.Ride__r.To_Location__c);
            }

            List<String> fromList = new List<String>(fromLocations);
            List<String> toList   = new List<String>(toLocations);
            fromList.sort();
            toList.sort();

            return new Map<String, Object>{
                'success'       => true,
                'fromLocations' => fromList,
                'toLocations'   => toList
            };

        } catch (Exception e) {
            return new Map<String, Object>{
                'success'       => false,
                'message'       => 'Failed to fetch location history: ' + e.getMessage(),
                'fromLocations' => new List<String>(),
                'toLocations'   => new List<String>()
            };
        }
    }

    // ─── MODAL DETAIL QUERIES ────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static Booking__c getBookingDetails(String bookingId) {
        try {
            return [
                SELECT Id, Ride__r.Id, Ride__r.From_Location__c, Ride__r.To_Location__c,
                       Ride__r.Departure_DateTime__c, Ride__r.Publisher__r.Name,
                       Ride__r.Publisher__r.Phone, Ride__r.Vehicle_Type__c,
                       Seats_Booked__c, Status__c, Booking_DateTime__c
                FROM Booking__c
                WHERE Id = :bookingId
                LIMIT 1
            ];
        } catch (Exception e) {
            throw new AuraHandledException('Failed to get booking details: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static Ride__c getRideDetails(String rideId) {
        try {
            return [
                SELECT Id, From_Location__c, To_Location__c, Departure_DateTime__c,
                       Available_Seats__c, Price_Per_Seat__c, Vehicle_Type__c,
                       Notes__c, Status__c,
                       (SELECT Id, Passenger__r.Name, Passenger__r.Phone, Seats_Booked__c
                        FROM Bookings__r
                        WHERE Status__c = 'Confirmed')
                FROM Ride__c
                WHERE Id = :rideId
                LIMIT 1
            ];
        } catch (Exception e) {
            throw new AuraHandledException('Failed to get ride details: ' + e.getMessage());
        }
    }

    // ─── UPDATE / CANCEL / DELETE ────────────────────────────────────────────

    @AuraEnabled
    public static Map<String, Object> updateBooking(String bookingId, Integer seatsBooked) {
        // NOTE: Passengers can only change their seat count.
        // Departure time is the publisher's data — removed from this method intentionally.
        try {
            Booking__c booking = [
                SELECT Id, Ride__c, Seats_Booked__c
                FROM Booking__c
                WHERE Id = :bookingId
                LIMIT 1
            ];

            Ride__c ride = [
                SELECT Id, Available_Seats__c
                FROM Ride__c
                WHERE Id = :booking.Ride__c
                LIMIT 1
            ];

            Integer seatDifference = seatsBooked - Integer.valueOf(booking.Seats_Booked__c);

            if (seatDifference > 0 && ride.Available_Seats__c < seatDifference) {
                return new Map<String, Object>{
                    'success' => false,
                    'message' => 'Not enough seats available for this update.'
                };
            }

            booking.Seats_Booked__c = seatsBooked;
            update booking;

            ride.Available_Seats__c -= seatDifference;
            update ride;

            return new Map<String, Object>{
                'success' => true,
                'message' => 'Booking updated successfully!'
            };

        } catch (Exception e) {
            return new Map<String, Object>{
                'success' => false,
                'message' => 'Failed to update booking: ' + e.getMessage()
            };
        }
    }

    @AuraEnabled
    public static Map<String, Object> cancelBooking(String bookingId) {
        try {
            Booking__c booking = [
                SELECT Id, Ride__c, Seats_Booked__c, Status__c
                FROM Booking__c
                WHERE Id = :bookingId
                LIMIT 1
            ];

            booking.Status__c = 'Cancelled';
            update booking;

            Ride__c ride = [SELECT Id, Available_Seats__c FROM Ride__c WHERE Id = :booking.Ride__c LIMIT 1];
            ride.Available_Seats__c += Integer.valueOf(booking.Seats_Booked__c);
            update ride;

            return new Map<String, Object>{
                'success' => true,
                'message' => 'Booking cancelled successfully!'
            };

        } catch (Exception e) {
            return new Map<String, Object>{
                'success' => false,
                'message' => 'Failed to cancel booking: ' + e.getMessage()
            };
        }
    }

    @AuraEnabled
    public static Map<String, Object> updateRide(String rideId, DateTime departureDateTime,
                                                 Integer availableSeats, Decimal pricePerSeat,
                                                 String vehicleType, String notes) {
        try {
            Ride__c ride = [
                SELECT Id, Available_Seats__c, Departure_DateTime__c,
                       Price_Per_Seat__c, Vehicle_Type__c, Notes__c
                FROM Ride__c
                WHERE Id = :rideId
                LIMIT 1
            ];

            ride.Departure_DateTime__c = departureDateTime;
            ride.Available_Seats__c    = availableSeats;
            ride.Price_Per_Seat__c     = pricePerSeat;
            ride.Vehicle_Type__c       = vehicleType;
            ride.Notes__c              = notes;
            update ride;

            return new Map<String, Object>{
                'success' => true,
                'message' => 'Ride updated successfully!'
            };

        } catch (Exception e) {
            return new Map<String, Object>{
                'success' => false,
                'message' => 'Failed to update ride: ' + e.getMessage()
            };
        }
    }

    @AuraEnabled
    public static Map<String, Object> deleteRide(String rideId) {
        try {
            List<Booking__c> bookings = [
                SELECT Id FROM Booking__c
                WHERE Ride__c   = :rideId
                AND   Status__c = 'Confirmed'
                LIMIT 1
            ];

            if (!bookings.isEmpty()) {
                return new Map<String, Object>{
                    'success' => false,
                    'message' => 'Cannot delete ride with confirmed bookings. Please cancel all bookings first.'
                };
            }

            delete [SELECT Id FROM Ride__c WHERE Id = :rideId LIMIT 1];

            return new Map<String, Object>{
                'success' => true,
                'message' => 'Ride deleted successfully!'
            };

        } catch (Exception e) {
            return new Map<String, Object>{
                'success' => false,
                'message' => 'Failed to delete ride: ' + e.getMessage()
            };
        }
    }

    // ─── PROFILE PICTURE ─────────────────────────────────────────────────────

    @AuraEnabled
    public static Map<String, Object> uploadProfilePicture(String userId, String fileName,
                                                           String base64Data, String contentType) {
        try {
            // Delete existing profile picture first
            List<ContentDocumentLink> existingLinks = [
                SELECT ContentDocumentId
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :userId
                AND ContentDocument.Title = 'ProfilePicture'
            ];
            if (!existingLinks.isEmpty()) {
                List<Id> docIds = new List<Id>();
                for (ContentDocumentLink link : existingLinks) docIds.add(link.ContentDocumentId);
                delete [SELECT Id FROM ContentDocument WHERE Id IN :docIds];
            }

            ContentVersion cv = new ContentVersion(
                Title           = 'ProfilePicture',
                PathOnClient    = fileName,
                VersionData     = EncodingUtil.base64Decode(base64Data),
                ContentLocation = 'S',
                IsMajorVersion  = true
            );
            insert cv;

            ContentVersion insertedCV = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1];

            insert new ContentDocumentLink(
                ContentDocumentId = insertedCV.ContentDocumentId,
                LinkedEntityId    = userId,
                ShareType         = 'V',
                Visibility        = 'AllUsers'
            );

            return new Map<String, Object>{ 'success' => true, 'message' => 'Profile picture uploaded successfully!' };

        } catch (Exception e) {
            return new Map<String, Object>{ 'success' => false, 'message' => 'Failed to upload profile picture: ' + e.getMessage() };
        }
    }

    @AuraEnabled
    public static Map<String, Object> getProfilePictureNonCacheable(String userId) {
        try {
            List<ContentDocumentLink> links = [
                SELECT ContentDocumentId
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :userId
                AND ContentDocument.Title = 'ProfilePicture'
                LIMIT 1
            ];

            if (links.isEmpty()) {
                return new Map<String, Object>{ 'success' => false, 'pictureUrl' => null };
            }

            ContentVersion cv = [
                SELECT Id FROM ContentVersion
                WHERE ContentDocumentId = :links[0].ContentDocumentId
                AND IsLatest = true
                LIMIT 1
            ];

            String pictureUrl = Url.getOrgDomainURL().toExternalForm()
                + '/sfc/servlet.shepherd/version/download/' + cv.Id;

            return new Map<String, Object>{ 'success' => true, 'pictureUrl' => pictureUrl };

        } catch (Exception e) {
            return new Map<String, Object>{ 'success' => false, 'pictureUrl' => null, 'message' => e.getMessage() };
        }
    }

    @AuraEnabled
    public static Map<String, Object> deleteProfilePicture(String userId) {
        try {
            List<ContentDocumentLink> existingLinks = [
                SELECT ContentDocumentId
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :userId
                AND ContentDocument.Title = 'ProfilePicture'
            ];

            if (existingLinks.isEmpty()) {
                return new Map<String, Object>{ 'success' => false, 'message' => 'No profile picture found to delete' };
            }

            List<Id> docIds = new List<Id>();
            for (ContentDocumentLink link : existingLinks) docIds.add(link.ContentDocumentId);
            delete [SELECT Id FROM ContentDocument WHERE Id IN :docIds];

            return new Map<String, Object>{ 'success' => true, 'message' => 'Profile picture deleted successfully!' };

        } catch (Exception e) {
            return new Map<String, Object>{ 'success' => false, 'message' => 'Failed to delete profile picture: ' + e.getMessage() };
        }
    }

    // ─── PASSWORD MIGRATION ──────────────────────────────────────────────────

    /**
     * One-time migration utility — hashes all plain-text passwords in the org.
     * Call this ONCE via Anonymous Apex after deploying this class.
     * Remove or comment out after migration is confirmed.
     */
    @AuraEnabled
    public static Map<String, Object> migratePasswordsToHash() {
        try {
            List<Account> accounts = [SELECT Id, Password__c FROM Account WHERE Password__c != null];
            List<Account> toUpdate = new List<Account>();

            for (Account acc : accounts) {
                // Only migrate if not already a SHA-256 base64 hash (44 chars)
                if (acc.Password__c.length() != 44) {
                    acc.Password__c = hashPassword(acc.Password__c);
                    toUpdate.add(acc);
                }
            }

            if (!toUpdate.isEmpty()) update toUpdate;

            return new Map<String, Object>{
                'success' => true,
                'message' => 'Migrated ' + toUpdate.size() + ' passwords to SHA-256 hashes.'
            };

        } catch (Exception e) {
            return new Map<String, Object>{
                'success' => false,
                'message' => 'Migration failed: ' + e.getMessage()
            };
        }
    }
}