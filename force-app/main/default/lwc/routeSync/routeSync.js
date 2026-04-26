// routeSync.js - v5.0
// Changes from v4:
//   - Removed import of refreshUserPublishedRides (method deleted from Apex)
//   - getUserPublishedRides now used everywhere (cacheable removed on Apex side)
//   - handleBookRide now passes searchForm.passengers as seat count
//   - searchResults mapped with driverInitials computed property
//   - updateBooking call no longer passes departureDateTime
//   - handleBookingEditChange: date/time fields removed from edit form

import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import registerUser from '@salesforce/apex/RouteSyncController.registerUser';
import loginUser from '@salesforce/apex/RouteSyncController.loginUser';
import publishRide from '@salesforce/apex/RouteSyncController.publishRide';
import searchRides from '@salesforce/apex/RouteSyncController.searchRides';
import bookRide from '@salesforce/apex/RouteSyncController.bookRide';
import getUserBookings from '@salesforce/apex/RouteSyncController.getUserBookings';
import getUserPublishedRides from '@salesforce/apex/RouteSyncController.getUserPublishedRides';
import getUserLocationHistory from '@salesforce/apex/RouteSyncController.getUserLocationHistory';
import updateBooking from '@salesforce/apex/RouteSyncController.updateBooking';
import cancelBooking from '@salesforce/apex/RouteSyncController.cancelBooking';
import updateRide from '@salesforce/apex/RouteSyncController.updateRide';
import deleteRide from '@salesforce/apex/RouteSyncController.deleteRide';
import getBookingDetails from '@salesforce/apex/RouteSyncController.getBookingDetails';
import getRideDetails from '@salesforce/apex/RouteSyncController.getRideDetails';
import uploadProfilePicture from '@salesforce/apex/RouteSyncController.uploadProfilePicture';
import getProfilePictureNonCacheable from '@salesforce/apex/RouteSyncController.getProfilePictureNonCacheable';
import deleteProfilePicture from '@salesforce/apex/RouteSyncController.deleteProfilePicture';
import search from '@salesforce/apex/MapplsAutosuggestService.search';
import searchWithCoordinates from '@salesforce/apex/MapplsAutosuggestService.searchWithCoordinates';

export default class RouteSync extends LightningElement {
    @track currentScreen = 'login';
    @track currentUser = null;
    @track isLoading = false;
    @track activeTab = 'search';
    @track activeRideSubTab = 'bookings';

    // Form data
    @track loginForm = { email: '', password: '' };
    @track registerForm = { name: '', email: '', phone: '', password: '', dateOfBirth: '', gender: '' };
    @track searchForm = { from: '', to: '', date: '', passengers: '1' };
    @track publishForm = { from: '', to: '', date: '', time: '', seats: 1, price: '', vehicleType: '', notes: '' };

    // Selected location GEO data — populated when user picks from autocomplete
    // Structure: { label, eLoc, latitude, longitude, city, state }
    @track searchFromGeo  = null;
    @track searchToGeo    = null;
    @track publishFromGeo = null;
    @track publishToGeo   = null;

    // Data
    @track searchResults = [];
    @track userBookings = [];
    @track userRides = [];
    @track hasSearched = false;

    // Booking confirmation modal
    @track showBookingConfirmModal = false;
    @track pendingBookingRide = null;

    // Location autocomplete
    @track allFromLocations = [];
    @track allToLocations = [];
    @track filteredFromLocations = [];
    @track filteredToLocations = [];
    @track showSearchFromSuggestions = false;
    @track showSearchToSuggestions = false;
    @track showPublishFromSuggestions = false;
    @track showPublishToSuggestions = false;

    // Ride/Booking detail modals
    @track showBookingModal = false;
    @track showRideModal = false;
    @track selectedBooking = null;
    @track selectedRide = null;
    @track ridePassengers = [];

    // Edit forms for modals — booking only has seatsBooked now (no date/time)
    @track editBookingForm = { seatsBooked: 1 };
    @track editRideForm = { date: '', time: '', availableSeats: 1, pricePerSeat: '', vehicleType: '', notes: '' };

    // Profile picture
    @track profilePictureUrl = null;

    // ── GETTERS ──────────────────────────────────────────────────────────────

    get isLoginScreen()     { return this.currentScreen === 'login'; }
    get isRegisterScreen()  { return this.currentScreen === 'register'; }
    get isDashboardScreen() { return this.currentScreen === 'dashboard'; }

    get isSearchActive()  { return this.activeTab === 'search'  ? 'nav-item active' : 'nav-item'; }
    get isPublishActive() { return this.activeTab === 'publish' ? 'nav-item active' : 'nav-item'; }
    get isRidesActive()   { return this.activeTab === 'rides'   ? 'nav-item active' : 'nav-item'; }
    get isInboxActive()   { return this.activeTab === 'inbox'   ? 'nav-item active' : 'nav-item'; }
    get isProfileActive() { return this.activeTab === 'profile' ? 'nav-item active' : 'nav-item'; }

    get showSearchTab()  { return this.activeTab === 'search'; }
    get showPublishTab() { return this.activeTab === 'publish'; }
    get showRidesTab()   { return this.activeTab === 'rides'; }
    get showInboxTab()   { return this.activeTab === 'inbox'; }
    get showProfileTab() { return this.activeTab === 'profile'; }

    get showNoResults()     { return this.hasSearched && this.searchResults.length === 0; }
    get showSearchResults() { return this.searchResults.length > 0; }

    get bookingsTabClass()  { return this.activeRideSubTab === 'bookings'  ? 'ride-tab active' : 'ride-tab'; }
    get publishedTabClass() { return this.activeRideSubTab === 'published' ? 'ride-tab active' : 'ride-tab'; }
    get showBookingsSection()  { return this.activeRideSubTab === 'bookings'; }
    get showPublishedSection() { return this.activeRideSubTab === 'published'; }

    get userInitials() { return this.currentUser ? this.getInitials(this.currentUser.Name) : '?'; }

    // Search results enriched with driver initials and self-check
    get enrichedSearchResults() {
        if (!this.searchResults || !this.currentUser) return this.searchResults;
        return this.searchResults.map(ride => ({
            ...ride,
            driverInitials: this.getInitials(ride.Publisher__r ? ride.Publisher__r.Name : '?'),
            isOwnRide: ride.Publisher__r && ride.Publisher__r.Id === this.currentUser.Id
        }));
    }

    // Booking confirmation modal computed values
    get confirmTotalPrice() {
        if (!this.pendingBookingRide) return 0;
        return (this.pendingBookingRide.Price_Per_Seat__c || 0) * parseInt(this.searchForm.passengers || 1);
    }

    get genderOptions() {
        return [
            { label: 'Male', value: 'Male' },
            { label: 'Female', value: 'Female' },
            { label: 'Other', value: 'Other' },
            { label: 'Prefer not to say', value: 'Prefer not to say' }
        ];
    }

    get vehicleOptions() {
        return [
            { label: '🚗 Car - Sedan', value: 'Car - Sedan' },
            { label: '🚙 Car - SUV', value: 'Car - SUV' },
            { label: '🚗 Car - Hatchback', value: 'Car - Hatchback' },
            { label: '🏍️ Motorcycle', value: 'Motorcycle' },
            { label: '🚌 Bus/Van', value: 'Bus/Van' }
        ];
    }

    get passengerOptions() {
        return [
            { label: '1 passenger', value: '1' },
            { label: '2 passengers', value: '2' },
            { label: '3 passengers', value: '3' },
            { label: '4+ passengers', value: '4' }
        ];
    }

    // ── FORM INPUT HANDLERS ──────────────────────────────────────────────────

    handleLoginInputChange(event) {
        this.loginForm[event.target.dataset.field] = event.target.value;
    }

    handleRegisterInputChange(event) {
        this.registerForm[event.target.dataset.field] = event.target.value;
    }

    async handleSearchInputChange(event) {
        const field = event.target.dataset.field;
        const value = event.target.value;
        this.searchForm[field] = value;
        // Clear cached geo when user types manually
        if (field === 'from') { this.searchFromGeo = null; await this.filterFromLocations(value); }
        else if (field === 'to') { this.searchToGeo = null; await this.filterToLocations(value); }
    }

    async handlePublishInputChange(event) {
        const field = event.target.dataset.field;
        const value = event.target.value;
        this.publishForm[field] = value;
        // Clear cached geo when user types manually
        if (field === 'from') { this.publishFromGeo = null; await this.filterFromLocations(value); }
        else if (field === 'to') { this.publishToGeo = null; await this.filterToLocations(value); }
    }

    // ── LOCATION AUTOCOMPLETE ────────────────────────────────────────────────

    async getSuggestedLocations(value) {
        if (!value || value.length < 2) return [];
        try {
            const results = await searchWithCoordinates({ query: value });
            console.log('searchWithCoordinates results:', JSON.stringify(results));
            if (results && results.length > 0) {
                return results.map(r => ({
                    label:   r.label,
                    geoJson: JSON.stringify(r)  // serialized for data-geo dataset attribute
                }));
            }
            return [];
        } catch (error) {
            console.error('searchWithCoordinates failed:', JSON.stringify(error));
            try {
                const labels = await search({ query: value });
                return labels.map(l => ({ label: l, geoJson: null }));
            } catch (e) {
                console.error('search fallback failed:', JSON.stringify(e));
                return [];
            }
        }
    }

    async filterFromLocations(inputValue) {
        if (!inputValue || inputValue.trim() === '') {
            this.filteredFromLocations = this.allFromLocations.map(l => ({ label: l, geoJson: null }));
            return;
        }
        const searchTerm = inputValue.toLowerCase();
        const historyMatches = this.allFromLocations.filter(l => l.toLowerCase().includes(searchTerm));

        if (historyMatches.length > 0 && inputValue.length < 3) {
            // Short input — just show history without geo (user still typing)
            this.filteredFromLocations = historyMatches.map(l => ({ label: l, geoJson: null }));
        } else {
            // Always call API to get geo-enriched results
            // Merge: API results first, then any history matches not in API results
            const apiResults = await this.getSuggestedLocations(inputValue);
            if (apiResults && apiResults.length > 0) {
                this.filteredFromLocations = apiResults;
            } else {
                this.filteredFromLocations = historyMatches.map(l => ({ label: l, geoJson: null }));
            }
        }
    }

    async filterToLocations(inputValue) {
        if (!inputValue || inputValue.trim() === '') {
            this.filteredToLocations = this.allToLocations.map(l => ({ label: l, geoJson: null }));
            return;
        }
        const searchTerm = inputValue.toLowerCase();
        const historyMatches = this.allToLocations.filter(l => l.toLowerCase().includes(searchTerm));

        if (historyMatches.length > 0 && inputValue.length < 3) {
            // Short input — just show history without geo (user still typing)
            this.filteredToLocations = historyMatches.map(l => ({ label: l, geoJson: null }));
        } else {
            // Always call API to get geo-enriched results
            const apiResults = await this.getSuggestedLocations(inputValue);
            if (apiResults && apiResults.length > 0) {
                this.filteredToLocations = apiResults;
            } else {
                this.filteredToLocations = historyMatches.map(l => ({ label: l, geoJson: null }));
            }
        }
    }

    handleSuggestionSelect(event) {
        const label   = event.currentTarget.dataset.location;
        const field   = event.currentTarget.dataset.field;
        const form    = event.currentTarget.dataset.form;
        const geoRaw  = event.currentTarget.dataset.geo;
        const geo     = geoRaw ? JSON.parse(geoRaw) : null;

        console.log('Suggestion selected:', label, '| geo:', JSON.stringify(geo));

        if (form === 'search') {
            this.searchForm[field] = label;
            if (field === 'from') { this.searchFromGeo = geo; this.showSearchFromSuggestions = false; }
            else                  { this.searchToGeo   = geo; this.showSearchToSuggestions   = false; }
        } else {
            this.publishForm[field] = label;
            if (field === 'from') { this.publishFromGeo = geo; this.showPublishFromSuggestions = false; }
            else                  { this.publishToGeo   = geo; this.showPublishToSuggestions   = false; }
        }
        console.log('searchFromGeo after select:', JSON.stringify(this.searchFromGeo));
        console.log('publishFromGeo after select:', JSON.stringify(this.publishFromGeo));
    }

    handleSearchFromFocus()   { this.filterFromLocations(this.searchForm.from); this.showSearchFromSuggestions = true; }
    handleSearchFromBlur()    { setTimeout(() => { this.showSearchFromSuggestions = false; }, 200); }
    handleSearchToFocus()     { this.filterToLocations(this.searchForm.to); this.showSearchToSuggestions = true; }
    handleSearchToBlur()      { setTimeout(() => { this.showSearchToSuggestions = false; }, 200); }
    handlePublishFromFocus()  { this.filterFromLocations(this.publishForm.from); this.showPublishFromSuggestions = true; }
    handlePublishFromBlur()   { setTimeout(() => { this.showPublishFromSuggestions = false; }, 200); }
    handlePublishToFocus()    { this.filterToLocations(this.publishForm.to); this.showPublishToSuggestions = true; }
    handlePublishToBlur()     { setTimeout(() => { this.showPublishToSuggestions = false; }, 200); }

    // ── NAVIGATION ───────────────────────────────────────────────────────────

    goToRegister(event) { event.preventDefault(); this.currentScreen = 'register'; }
    goToLogin(event)    { event.preventDefault(); this.currentScreen = 'login'; }

    handleTabClick(event) {
        event.preventDefault();
        const tab = event.currentTarget.dataset.tab;
        if (tab) {
            this.activeTab = tab;
            if (tab === 'rides') this.activeRideSubTab = 'bookings';
        }
    }

    handleRideSubTabClick(event) {
        event.preventDefault();
        const subtab = event.currentTarget.dataset.subtab;
        if (subtab) this.activeRideSubTab = subtab;
    }

    // ── AUTHENTICATION ───────────────────────────────────────────────────────

    async handleLogin() {
        if (!this.loginForm.email || !this.loginForm.password) {
            this.showToast('Error', 'Please fill in all required fields', 'error');
            return;
        }
        this.isLoading = true;
        try {
            const result = await loginUser({ email: this.loginForm.email, password: this.loginForm.password });
            if (result.success) {
                this.currentUser = result.user;
                this.currentScreen = 'dashboard';
                this.activeTab = 'search';
                this.showToast('Success', result.message, 'success');
                await this.loadUserData();
                await this.loadLocationHistory();
                await this.loadProfilePicture();
            } else {
                this.showToast('Error', result.message, 'error');
            }
        } catch (error) {
            this.showToast('Error', 'Login failed: ' + error.body.message, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async handleRegister() {
        if (!this.registerForm.name || !this.registerForm.email ||
            !this.registerForm.phone || !this.registerForm.password) {
            this.showToast('Error', 'Please fill in all required fields', 'error');
            return;
        }
        this.isLoading = true;
        try {
            const result = await registerUser({
                name: this.registerForm.name,
                email: this.registerForm.email,
                phone: this.registerForm.phone,
                password: this.registerForm.password,
                dateOfBirth: this.registerForm.dateOfBirth || null,
                gender: this.registerForm.gender || null
            });
            if (result.success) {
                this.showToast('Success', result.message, 'success');
                this.currentScreen = 'login';
                this.resetForms();
            } else {
                this.showToast('Error', result.message, 'error');
            }
        } catch (error) {
            this.showToast('Error', 'Registration failed: ' + error.body.message, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // ── SEARCH ───────────────────────────────────────────────────────────────

    async handleSearchRides() {
        if (!this.searchForm.from || !this.searchForm.to || !this.searchForm.date) {
            this.showToast('Error', 'Please fill in all search criteria', 'error');
            return;
        }
        this.isLoading = true;
        this.hasSearched = true;
        try {
            this.searchResults = await searchRides({
                fromLocation: this.searchForm.from,
                toLocation:   this.searchForm.to,
                travelDate:   this.searchForm.date,
                passengers:   parseInt(this.searchForm.passengers || 1),
                // Geo params — null if user typed manually without picking a suggestion
                fromLat:  this.searchFromGeo ? this.searchFromGeo.latitude  : null,
                fromLng:  this.searchFromGeo ? this.searchFromGeo.longitude : null,
                toLat:    this.searchToGeo   ? this.searchToGeo.latitude    : null,
                toLng:    this.searchToGeo   ? this.searchToGeo.longitude   : null,
                radiusKm: 30
            });
            if (this.searchResults.length === 0) {
                this.showToast('Info', 'No rides found for your search criteria', 'info');
            }
        } catch (error) {
            this.showToast('Error', 'Search failed: ' + error.body.message, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // ── BOOKING CONFIRMATION MODAL ───────────────────────────────────────────

    handleBookRide(event) {
        // Find the ride from enrichedSearchResults
        const rideId = event.target.dataset.rideid;
        const ride = this.searchResults.find(r => r.Id === rideId);
        if (!ride) return;

        // Show confirmation modal instead of booking immediately
        this.pendingBookingRide = ride;
        this.showBookingConfirmModal = true;
    }

    closeBookingConfirmModal() {
        this.showBookingConfirmModal = false;
        this.pendingBookingRide = null;
    }

    async handleConfirmBooking() {
        if (!this.pendingBookingRide) return;
        this.isLoading = true;
        this.showBookingConfirmModal = false;
        try {
            const result = await bookRide({
                rideId: this.pendingBookingRide.Id,
                passengerId: this.currentUser.Id,
                seatsBooked: parseInt(this.searchForm.passengers || 1)
            });
            if (result.success) {
                this.showToast('Success', result.message, 'success');
                await this.loadUserBookings();
                await this.loadLocationHistory();
                await this.handleSearchRides();
            } else {
                this.showToast('Error', result.message, 'error');
            }
        } catch (error) {
            this.showToast('Error', 'Booking failed: ' + error.body.message, 'error');
        } finally {
            this.isLoading = false;
            this.pendingBookingRide = null;
        }
    }

    // ── PUBLISH ──────────────────────────────────────────────────────────────

    async handlePublishRide() {
        if (!this.publishForm.from || !this.publishForm.to || !this.publishForm.date ||
            !this.publishForm.time || !this.publishForm.price || !this.publishForm.vehicleType) {
            this.showToast('Error', 'Please fill in all required fields', 'error');
            return;
        }
        this.isLoading = true;
        try {
            const departureDateTime = new Date(this.publishForm.date + 'T' + this.publishForm.time);
            const fg = this.publishFromGeo;
            const tg = this.publishToGeo;

            const result = await publishRide({
                userId:           this.currentUser.Id,
                fromLocation:     this.publishForm.from,
                toLocation:       this.publishForm.to,
                departureDateTime,
                availableSeats:   parseInt(this.publishForm.seats),
                pricePerSeat:     parseFloat(this.publishForm.price),
                vehicleType:      this.publishForm.vehicleType,
                notes:            this.publishForm.notes,
                // Geo — from selected autocomplete suggestion (null if typed manually)
                fromELoc:  fg ? fg.eLoc      : null,
                fromLat:   fg ? fg.latitude  : null,
                fromLng:   fg ? fg.longitude : null,
                fromCity:  fg ? fg.city      : null,
                fromState: fg ? fg.state     : null,
                toELoc:    tg ? tg.eLoc      : null,
                toLat:     tg ? tg.latitude  : null,
                toLng:     tg ? tg.longitude : null,
                toCity:    tg ? tg.city      : null,
                toState:   tg ? tg.state     : null
            });
            if (result.success) {
                this.showToast('Success', result.message, 'success');
                this.resetPublishForm();
                this.userRides = await getUserPublishedRides({ userId: this.currentUser.Id });
                await this.loadLocationHistory();
                this.activeTab = 'rides';
                this.activeRideSubTab = 'published';
            } else {
                this.showToast('Error', result.message, 'error');
            }
        } catch (error) {
            this.showToast('Error', 'Failed to publish ride: ' + error.body.message, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // ── BOOKING DETAIL MODAL ─────────────────────────────────────────────────

    async handleBookingClick(event) {
        const bookingId = event.currentTarget.dataset.bookingid;
        this.isLoading = true;
        try {
            const booking = await getBookingDetails({ bookingId });
            this.selectedBooking = booking;
            // Only seats — no date/time editing for passengers
            this.editBookingForm = { seatsBooked: booking.Seats_Booked__c };
            this.showBookingModal = true;
        } catch (error) {
            this.showToast('Error', 'Failed to load booking details: ' + error.body.message, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    closeBookingModal() {
        this.showBookingModal = false;
        this.selectedBooking = null;
        this.editBookingForm = { seatsBooked: 1 };
    }

    handleBookingEditChange(event) {
        this.editBookingForm[event.target.dataset.field] = event.target.value;
    }

    async handleSaveBooking() {
        this.isLoading = true;
        try {
            // Note: no departureDateTime — Apex updateBooking no longer accepts it
            const result = await updateBooking({
                bookingId: this.selectedBooking.Id,
                seatsBooked: parseInt(this.editBookingForm.seatsBooked)
            });
            if (result.success) {
                this.showToast('Success', result.message, 'success');
                this.closeBookingModal();
                await this.loadUserBookings();
            } else {
                this.showToast('Error', result.message, 'error');
            }
        } catch (error) {
            this.showToast('Error', 'Failed to update booking: ' + error.body.message, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async handleCancelBooking() {
        if (!confirm('Are you sure you want to cancel this booking?')) return;
        this.isLoading = true;
        try {
            const result = await cancelBooking({ bookingId: this.selectedBooking.Id });
            if (result.success) {
                this.showToast('Success', result.message, 'success');
                this.closeBookingModal();
                await this.loadUserBookings();
            } else {
                this.showToast('Error', result.message, 'error');
            }
        } catch (error) {
            this.showToast('Error', 'Failed to cancel booking: ' + error.body.message, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // ── RIDE DETAIL MODAL ────────────────────────────────────────────────────

    async handleRideClick(event) {
        const rideId = event.currentTarget.dataset.rideid;
        this.isLoading = true;
        try {
            const ride = await getRideDetails({ rideId });
            this.selectedRide = ride;
            const dt = new Date(ride.Departure_DateTime__c);
            this.editRideForm = {
                date: this.formatDate(dt),
                time: this.formatTime(dt),
                availableSeats: ride.Available_Seats__c,
                pricePerSeat: ride.Price_Per_Seat__c,
                vehicleType: ride.Vehicle_Type__c,
                notes: ride.Notes__c || ''
            };
            this.ridePassengers = (ride.Bookings__r || []).map(b => ({
                ...b,
                initials: this.getInitials(b.Passenger__r.Name)
            }));
            this.showRideModal = true;
        } catch (error) {
            this.showToast('Error', 'Failed to load ride details: ' + error.body.message, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    closeRideModal() {
        this.showRideModal = false;
        this.selectedRide = null;
        this.ridePassengers = [];
        this.editRideForm = { date: '', time: '', availableSeats: 1, pricePerSeat: '', vehicleType: '', notes: '' };
    }

    handleRideEditChange(event) {
        this.editRideForm[event.target.dataset.field] = event.target.value;
    }

    async handleSaveRide() {
        this.isLoading = true;
        try {
            const departureDateTime = new Date(this.editRideForm.date + 'T' + this.editRideForm.time);
            const result = await updateRide({
                rideId: this.selectedRide.Id,
                departureDateTime,
                availableSeats: parseInt(this.editRideForm.availableSeats),
                pricePerSeat: parseFloat(this.editRideForm.pricePerSeat),
                vehicleType: this.editRideForm.vehicleType,
                notes: this.editRideForm.notes
            });
            if (result.success) {
                this.showToast('Success', result.message, 'success');
                this.closeRideModal();
                await this.loadUserRides();
            } else {
                this.showToast('Error', result.message, 'error');
            }
        } catch (error) {
            this.showToast('Error', 'Failed to update ride: ' + error.body.message, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async handleDeleteRide() {
        if (!confirm('Are you sure you want to delete this ride? This cannot be undone.')) return;
        this.isLoading = true;
        try {
            const result = await deleteRide({ rideId: this.selectedRide.Id });
            if (result.success) {
                this.showToast('Success', result.message, 'success');
                this.closeRideModal();
                await this.loadUserRides();
            } else {
                this.showToast('Error', result.message, 'error');
            }
        } catch (error) {
            this.showToast('Error', 'Failed to delete ride: ' + error.body.message, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // ── DATA LOADING ─────────────────────────────────────────────────────────

    async loadUserData() {
        await this.loadUserBookings();
        await this.loadUserRides();
    }

    async loadUserBookings() {
        try {
            this.userBookings = await getUserBookings({ userId: this.currentUser.Id });
        } catch (error) {
            console.error('Failed to load bookings:', error);
        }
    }

    async loadUserRides() {
        try {
            this.userRides = await getUserPublishedRides({ userId: this.currentUser.Id });
        } catch (error) {
            console.error('Failed to load published rides:', error);
        }
    }

    async loadLocationHistory() {
        try {
            const result = await getUserLocationHistory({ userId: this.currentUser.Id });
            if (result.success) {
                this.allFromLocations = result.fromLocations || [];
                this.allToLocations   = result.toLocations   || [];
                this.filteredFromLocations = [...this.allFromLocations];
                this.filteredToLocations   = [...this.allToLocations];
            }
        } catch (error) {
            console.error('Failed to load location history:', error);
        }
    }

    // ── PROFILE PICTURE ──────────────────────────────────────────────────────

    async loadProfilePicture() {
        try {
            const result = await getProfilePictureNonCacheable({ userId: this.currentUser.Id });
            this.profilePictureUrl = result.success ? result.pictureUrl : null;
        } catch (error) {
            this.profilePictureUrl = null;
        }
    }

    handleProfilePictureUpload(event) {
        const file = event.target.files[0];
        if (!file) return;
        if (!file.type.startsWith('image/')) {
            this.showToast('Error', 'Please select a valid image file', 'error');
            return;
        }
        if (file.size > 5 * 1024 * 1024) {
            this.showToast('Error', 'Image size should be less than 5MB', 'error');
            return;
        }
        this.isLoading = true;
        const reader = new FileReader();
        reader.onload = async () => {
            try {
                const base64 = reader.result.split(',')[1];
                const result = await uploadProfilePicture({
                    userId: this.currentUser.Id,
                    fileName: file.name,
                    base64Data: base64,
                    contentType: file.type
                });
                if (result.success) {
                    this.showToast('Success', 'Profile picture updated successfully', 'success');
                    await this.loadProfilePicture();
                } else {
                    this.showToast('Error', result.message, 'error');
                }
            } catch (error) {
                this.showToast('Error', 'Failed to upload: ' + (error.body ? error.body.message : error.message), 'error');
            } finally {
                this.isLoading = false;
                event.target.value = '';
            }
        };
        reader.onerror = () => { this.showToast('Error', 'Failed to read the file', 'error'); this.isLoading = false; };
        reader.readAsDataURL(file);
    }

    async handleDeleteProfilePicture() {
        if (!confirm('Are you sure you want to delete your profile picture?')) return;
        this.isLoading = true;
        try {
            const result = await deleteProfilePicture({ userId: this.currentUser.Id });
            if (result.success) {
                this.showToast('Success', 'Profile picture deleted successfully', 'success');
                this.profilePictureUrl = null;
            } else {
                this.showToast('Error', result.message, 'error');
            }
        } catch (error) {
            this.showToast('Error', 'Failed to delete: ' + (error.body ? error.body.message : error.message), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // ── LOGOUT ───────────────────────────────────────────────────────────────

    handleLogout() {
        this.currentUser = null;
        this.currentScreen = 'login';
        this.activeTab = 'search';
        this.activeRideSubTab = 'bookings';
        this.resetForms();
        this.searchResults = [];
        this.userBookings = [];
        this.userRides = [];
        this.hasSearched = false;
        this.allFromLocations = [];
        this.allToLocations = [];
        this.filteredFromLocations = [];
        this.filteredToLocations = [];
        this.showSearchFromSuggestions = false;
        this.showSearchToSuggestions = false;
        this.showPublishFromSuggestions = false;
        this.showPublishToSuggestions = false;
        this.profilePictureUrl = null;
        this.showBookingConfirmModal = false;
        this.pendingBookingRide = null;
        this.searchFromGeo  = null;
        this.searchToGeo    = null;
        this.publishFromGeo = null;
        this.publishToGeo   = null;
        this._geoCache      = {};
        this.showToast('Success', 'Logged out successfully', 'success');
    }

    // ── UTILITIES ────────────────────────────────────────────────────────────

    formatDate(date) {
        const y = date.getFullYear();
        const m = String(date.getMonth() + 1).padStart(2, '0');
        const d = String(date.getDate()).padStart(2, '0');
        return `${y}-${m}-${d}`;
    }

    formatTime(date) {
        const h = String(date.getHours()).padStart(2, '0');
        const m = String(date.getMinutes()).padStart(2, '0');
        return `${h}:${m}`;
    }

    getInitials(name) {
        if (!name) return '?';
        const parts = name.trim().split(' ');
        if (parts.length === 1) return parts[0].charAt(0).toUpperCase();
        return (parts[0].charAt(0) + parts[parts.length - 1].charAt(0)).toUpperCase();
    }

    resetForms() {
        this.loginForm    = { email: '', password: '' };
        this.registerForm = { name: '', email: '', phone: '', password: '', dateOfBirth: '', gender: '' };
    }

    resetPublishForm() {
        this.publishForm    = { from: '', to: '', date: '', time: '', seats: 1, price: '', vehicleType: '', notes: '' };
        this.publishFromGeo = null;
        this.publishToGeo   = null;
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}