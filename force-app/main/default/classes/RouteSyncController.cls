/**
* @File Name : RouteSyncController.cls
* @Description : Complete controller with all CRUD and profile picture methods
* @Author :
* @Last Modified By :
* @Last Modified On : November 01, 2025
* @Modification Log :
*==============================================================================
* Ver | Date | Author | Modification
*==============================================================================
* 1.0 | September 6, 2025 |   | Initial Version
* 2.0 | October 28, 2025 |   | Added getUserLocationHistory method
* 3.0 | October 29, 2025 |   | Added modal CRUD methods
* 4.0 | November 01, 2025 |   | Added profile picture with delete
*==============================================================================
**/

public without sharing class RouteSyncController {
    
    @AuraEnabled
    public static Map<String, Object> registerUser(String name, String email, String phone, 
                                                  String password, Date dateOfBirth, String gender) {
        try {
            List<Account> existingAccounts = [SELECT Id FROM Account WHERE Email__c = :email LIMIT 1];
            if (!existingAccounts.isEmpty()) {
                return new Map<String, Object>{
                    'success' => false,
                    'message' => 'Email already registered. Please use a different email.'
                };
            }
            
            Account newUser = new Account(
                Name = name,
                Email__c = email,
                Phone = phone,
                Password__c = password,
                Date_of_Birth__c = dateOfBirth,
                Gender__c = gender,
                Type = 'Person Account'
            );
            
            insert newUser;
            
            return new Map<String, Object>{
                'success' => true,
                'message' => 'Registration successful!',
                'userId' => newUser.Id
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
            List<Account> users = [SELECT Id, Name, Email__c, Phone FROM Account 
                                  WHERE Email__c = :email AND Password__c = :password LIMIT 1];
            
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
                'user' => user
            };
            
        } catch (Exception e) {
            return new Map<String, Object>{
                'success' => false,
                'message' => 'Login failed: ' + e.getMessage()
            };
        }
    }
    
    @AuraEnabled
    public static Map<String, Object> publishRide(String userId, String fromLocation, String toLocation,
                                                 DateTime departureDateTime, Integer availableSeats,
                                                 Decimal pricePerSeat, String vehicleType, String notes) {
        try {
            Ride__c newRide = new Ride__c(
                Publisher__c = userId,
                From_Location__c = fromLocation,
                To_Location__c = toLocation,
                Departure_DateTime__c = departureDateTime,
                Available_Seats__c = availableSeats,
                Price_Per_Seat__c = pricePerSeat,
                Vehicle_Type__c = vehicleType,
                Notes__c = notes,
                Status__c = 'Active'
            );
            
            insert newRide;
            
            return new Map<String, Object>{
                'success' => true,
                'message' => 'Ride published successfully!',
                'rideId' => newRide.Id
            };
            
        } catch (Exception e) {
            return new Map<String, Object>{
                'success' => false,
                'message' => 'Failed to publish ride: ' + e.getMessage()
            };
        }
    }
    
    @AuraEnabled(cacheable=true)
    public static List<Ride__c> searchRides(String fromLocation, String toLocation, Date travelDate, Integer passengers) {
        try {
            DateTime startOfDay = DateTime.newInstance(travelDate, Time.newInstance(0, 0, 0, 0));
            DateTime endOfDay = DateTime.newInstance(travelDate, Time.newInstance(23, 59, 59, 999));
            
            return [SELECT Id, Publisher__r.Name, From_Location__c, To_Location__c, 
                          Departure_DateTime__c, Available_Seats__c, Price_Per_Seat__c,
                          Vehicle_Type__c, Notes__c, Publisher__r.Phone
                   FROM Ride__c 
                   WHERE From_Location__c LIKE :('%' + fromLocation + '%')
                   AND To_Location__c LIKE :('%' + toLocation + '%')
                   AND Departure_DateTime__c >= :startOfDay
                   AND Departure_DateTime__c <= :endOfDay
                   AND Available_Seats__c >= :passengers
                   AND Status__c = 'Active'
                   ORDER BY Departure_DateTime__c ASC];
                   
        } catch (Exception e) {
            throw new AuraHandledException('Failed to search rides: ' + e.getMessage());
        }
    }
    
    @AuraEnabled
    public static Map<String, Object> bookRide(String rideId, String passengerId, Integer seatsBooked) {
        try {
            Ride__c ride = [SELECT Id, Available_Seats__c FROM Ride__c WHERE Id = :rideId LIMIT 1];
            
            if (ride.Available_Seats__c < seatsBooked) {
                return new Map<String, Object>{
                    'success' => false,
                    'message' => 'Not enough seats available'
                };
            }
            
            Booking__c newBooking = new Booking__c(
                Ride__c = rideId,
                Passenger__c = passengerId,
                Seats_Booked__c = seatsBooked,
                Status__c = 'Confirmed',
                Booking_DateTime__c = System.now()
            );
            
            insert newBooking;
            
            ride.Available_Seats__c -= seatsBooked;
            update ride;
            
            return new Map<String, Object>{
                'success' => true,
                'message' => 'Ride booked successfully!',
                'bookingId' => newBooking.Id
            };
            
        } catch (Exception e) {
            return new Map<String, Object>{
                'success' => false,
                'message' => 'Failed to book ride: ' + e.getMessage()
            };
        }
    }
    
    @AuraEnabled(cacheable=true)
    public static List<Booking__c> getUserBookings(String userId) {
        return [SELECT Id, Ride__r.From_Location__c, Ride__r.To_Location__c,
                      Ride__r.Departure_DateTime__c, Seats_Booked__c, Status__c,
                      Ride__r.Publisher__r.Name, Ride__r.Publisher__r.Phone,
                      Booking_DateTime__c, Ride__r.Vehicle_Type__c
               FROM Booking__c 
               WHERE Passenger__c = :userId
               ORDER BY CreatedDate DESC];
    }
    
    @AuraEnabled(cacheable=true)
    public static List<Ride__c> getUserPublishedRides(String userId) {
        return [SELECT Id, From_Location__c, To_Location__c, Departure_DateTime__c,
                      Available_Seats__c, Price_Per_Seat__c, Status__c,
                      Vehicle_Type__c, Notes__c,
                      (SELECT Id, Passenger__r.Name, Seats_Booked__c FROM Bookings__r)
               FROM Ride__c 
               WHERE Publisher__c = :userId
               ORDER BY CreatedDate DESC];
    }

    @AuraEnabled
    public static List<Ride__c> refreshUserPublishedRides(String userId) {
        return [SELECT Id, From_Location__c, To_Location__c, Departure_DateTime__c,
                    Available_Seats__c, Price_Per_Seat__c, Status__c,
                    (SELECT Id, Passenger__r.Name, Seats_Booked__c FROM Bookings__r)
            FROM Ride__c 
            WHERE Publisher__c = :userId
            ORDER BY CreatedDate DESC];
    }
    
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getUserLocationHistory(String userId) {
        try {
            Set<String> fromLocations = new Set<String>();
            Set<String> toLocations = new Set<String>();
            
            List<Ride__c> publishedRides = [SELECT From_Location__c, To_Location__c 
                                           FROM Ride__c 
                                           WHERE Publisher__c = :userId 
                                           ORDER BY CreatedDate DESC 
                                           LIMIT 50];
            
            for (Ride__c ride : publishedRides) {
                if (String.isNotBlank(ride.From_Location__c)) {
                    fromLocations.add(ride.From_Location__c);
                }
                if (String.isNotBlank(ride.To_Location__c)) {
                    toLocations.add(ride.To_Location__c);
                }
            }
            
            List<Booking__c> bookings = [SELECT Ride__r.From_Location__c, Ride__r.To_Location__c 
                                        FROM Booking__c 
                                        WHERE Passenger__c = :userId 
                                        ORDER BY CreatedDate DESC 
                                        LIMIT 50];
            
            for (Booking__c booking : bookings) {
                if (String.isNotBlank(booking.Ride__r.From_Location__c)) {
                    fromLocations.add(booking.Ride__r.From_Location__c);
                }
                if (String.isNotBlank(booking.Ride__r.To_Location__c)) {
                    toLocations.add(booking.Ride__r.To_Location__c);
                }
            }
            
            List<String> fromLocationsList = new List<String>(fromLocations);
            List<String> toLocationsList = new List<String>(toLocations);
            fromLocationsList.sort();
            toLocationsList.sort();
            
            return new Map<String, Object>{
                'success' => true,
                'fromLocations' => fromLocationsList,
                'toLocations' => toLocationsList
            };
            
        } catch (Exception e) {
            return new Map<String, Object>{
                'success' => false,
                'message' => 'Failed to fetch location history: ' + e.getMessage(),
                'fromLocations' => new List<String>(),
                'toLocations' => new List<String>()
            };
        }
    }
    
    @AuraEnabled(cacheable=true)
    public static Booking__c getBookingDetails(String bookingId) {
        try {
            return [SELECT Id, Ride__r.Id, Ride__r.From_Location__c, Ride__r.To_Location__c,
                          Ride__r.Departure_DateTime__c, Ride__r.Publisher__r.Name, 
                          Ride__r.Publisher__r.Phone, Ride__r.Vehicle_Type__c,
                          Seats_Booked__c, Status__c, Booking_DateTime__c
                   FROM Booking__c 
                   WHERE Id = :bookingId 
                   LIMIT 1];
        } catch (Exception e) {
            throw new AuraHandledException('Failed to get booking details: ' + e.getMessage());
        }
    }
    
    @AuraEnabled(cacheable=true)
    public static Ride__c getRideDetails(String rideId) {
        try {
            return [SELECT Id, From_Location__c, To_Location__c, Departure_DateTime__c,
                          Available_Seats__c, Price_Per_Seat__c, Vehicle_Type__c, 
                          Notes__c, Status__c,
                          (SELECT Id, Passenger__r.Name, Passenger__r.Phone, 
                                  Seats_Booked__c 
                           FROM Bookings__r 
                           WHERE Status__c = 'Confirmed')
                   FROM Ride__c 
                   WHERE Id = :rideId 
                   LIMIT 1];
        } catch (Exception e) {
            throw new AuraHandledException('Failed to get ride details: ' + e.getMessage());
        }
    }
    
    @AuraEnabled
    public static Map<String, Object> updateBooking(String bookingId, DateTime departureDateTime, 
                                                    Integer seatsBooked) {
        try {
            Booking__c booking = [SELECT Id, Ride__c, Seats_Booked__c 
                                 FROM Booking__c 
                                 WHERE Id = :bookingId 
                                 LIMIT 1];
            
            Ride__c ride = [SELECT Id, Available_Seats__c, Departure_DateTime__c 
                           FROM Ride__c 
                           WHERE Id = :booking.Ride__c 
                           LIMIT 1];
            
            Integer seatDifference = seatsBooked - Integer.valueOf(booking.Seats_Booked__c);
            
            if (seatDifference > 0 && ride.Available_Seats__c < seatDifference) {
                return new Map<String, Object>{
                    'success' => false,
                    'message' => 'Not enough seats available for this update'
                };
            }
            
            booking.Seats_Booked__c = seatsBooked;
            update booking;
            
            ride.Departure_DateTime__c = departureDateTime;
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
            Booking__c booking = [SELECT Id, Ride__c, Seats_Booked__c, Status__c 
                                 FROM Booking__c 
                                 WHERE Id = :bookingId 
                                 LIMIT 1];
            
            booking.Status__c = 'Cancelled';
            update booking;
            
            Ride__c ride = [SELECT Id, Available_Seats__c 
                           FROM Ride__c 
                           WHERE Id = :booking.Ride__c 
                           LIMIT 1];
            
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
            Ride__c ride = [SELECT Id, Available_Seats__c, Departure_DateTime__c, 
                                  Price_Per_Seat__c, Vehicle_Type__c, Notes__c 
                           FROM Ride__c 
                           WHERE Id = :rideId 
                           LIMIT 1];
            
            ride.Departure_DateTime__c = departureDateTime;
            ride.Available_Seats__c = availableSeats;
            ride.Price_Per_Seat__c = pricePerSeat;
            ride.Vehicle_Type__c = vehicleType;
            ride.Notes__c = notes;
            
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
            List<Booking__c> bookings = [SELECT Id 
                                        FROM Booking__c 
                                        WHERE Ride__c = :rideId 
                                        AND Status__c = 'Confirmed' 
                                        LIMIT 1];
            
            if (!bookings.isEmpty()) {
                return new Map<String, Object>{
                    'success' => false,
                    'message' => 'Cannot delete ride with confirmed bookings. Please cancel all bookings first.'
                };
            }
            
            Ride__c ride = [SELECT Id FROM Ride__c WHERE Id = :rideId LIMIT 1];
            delete ride;
            
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
    
    @AuraEnabled
    public static Map<String, Object> uploadProfilePicture(String userId, String fileName, 
                                                           String base64Data, String contentType) {
        try {
            List<ContentDocumentLink> existingLinks = [
                SELECT ContentDocumentId 
                FROM ContentDocumentLink 
                WHERE LinkedEntityId = :userId 
                AND ContentDocument.Title = 'ProfilePicture'
            ];
            
            if (!existingLinks.isEmpty()) {
                List<Id> documentIds = new List<Id>();
                for (ContentDocumentLink link : existingLinks) {
                    documentIds.add(link.ContentDocumentId);
                }
                List<ContentDocument> docsToDelete = [
                    SELECT Id FROM ContentDocument WHERE Id IN :documentIds
                ];
                delete docsToDelete;
            }
            
            ContentVersion cv = new ContentVersion();
            cv.Title = 'ProfilePicture';
            cv.PathOnClient = fileName;
            cv.VersionData = EncodingUtil.base64Decode(base64Data);
            cv.ContentLocation = 'S';
            cv.IsMajorVersion = true;
            insert cv;
            
            ContentVersion insertedCV = [
                SELECT ContentDocumentId 
                FROM ContentVersion 
                WHERE Id = :cv.Id 
                LIMIT 1
            ];
            
            ContentDocumentLink cdl = new ContentDocumentLink();
            cdl.ContentDocumentId = insertedCV.ContentDocumentId;
            cdl.LinkedEntityId = userId;
            cdl.ShareType = 'V';
            cdl.Visibility = 'AllUsers';
            insert cdl;
            
            return new Map<String, Object>{
                'success' => true,
                'message' => 'Profile picture uploaded successfully!'
            };
            
        } catch (Exception e) {
            return new Map<String, Object>{
                'success' => false,
                'message' => 'Failed to upload profile picture: ' + e.getMessage()
            };
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
                return new Map<String, Object>{
                    'success' => false,
                    'pictureUrl' => null
                };
            }
            
            ContentVersion cv = [
                SELECT Id 
                FROM ContentVersion 
                WHERE ContentDocumentId = :links[0].ContentDocumentId 
                AND IsLatest = true 
                LIMIT 1
            ];
            
            String baseUrl = Url.getOrgDomainURL().toExternalForm();
            String pictureUrl = baseUrl + '/sfc/servlet.shepherd/version/download/' + cv.Id;
            
            return new Map<String, Object>{
                'success' => true,
                'pictureUrl' => pictureUrl
            };
            
        } catch (Exception e) {
            return new Map<String, Object>{
                'success' => false,
                'pictureUrl' => null,
                'message' => e.getMessage()
            };
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
                return new Map<String, Object>{
                    'success' => false,
                    'message' => 'No profile picture found to delete'
                };
            }
            
            List<Id> documentIds = new List<Id>();
            for (ContentDocumentLink link : existingLinks) {
                documentIds.add(link.ContentDocumentId);
            }
            
            List<ContentDocument> docsToDelete = [
                SELECT Id FROM ContentDocument WHERE Id IN :documentIds
            ];
            delete docsToDelete;
            
            return new Map<String, Object>{
                'success' => true,
                'message' => 'Profile picture deleted successfully!'
            };
            
        } catch (Exception e) {
            return new Map<String, Object>{
                'success' => false,
                'message' => 'Failed to delete profile picture: ' + e.getMessage()
            };
        }
    }
}