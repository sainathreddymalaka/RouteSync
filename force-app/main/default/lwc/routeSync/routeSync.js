// routeSync.js - FINAL VERSION WITH PROFILE PICTURE FIX
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
import refreshUserPublishedRides from '@salesforce/apex/RouteSyncController.refreshUserPublishedRides';

export default class RouteSync extends LightningElement {
    @track currentScreen = 'login';
    @track currentUser = null;
    @track isLoading = false;
    @track activeTab = 'search';
    @track activeRideSubTab = 'bookings';
    
    // Form data
    @track loginForm = { email: '', password: '' };
    @track registerForm = { name: '', email: '', phone: '', password: '', dateOfBirth: '', gender: '' };
    @track searchForm = { from: '', to: '', date: '', passengers: 1 };
    @track publishForm = { from: '', to: '', date: '', time: '', seats: 1, price: '', vehicleType: '', notes: '' };
    
    // Data
    @track searchResults = [];
    @track userBookings = [];
    @track userRides = [];
    @track hasSearched = false;
    
    // Location history for autocomplete
    @track allFromLocations = [];
    @track allToLocations = [];
    @track filteredFromLocations = [];
    @track filteredToLocations = [];
    
    // Show/hide suggestion dropdowns
    @track showSearchFromSuggestions = false;
    @track showSearchToSuggestions = false;
    @track showPublishFromSuggestions = false;
    @track showPublishToSuggestions = false;
    
    // Modal states
    @track showBookingModal = false;
    @track showRideModal = false;
    @track selectedBooking = null;
    @track selectedRide = null;
    @track ridePassengers = [];
    
    // Edit forms for modals
    @track editBookingForm = { date: '', time: '', seatsBooked: 1 };
    @track editRideForm = { date: '', time: '', availableSeats: 1, pricePerSeat: '', vehicleType: '', notes: '' };
    
    // Profile picture
    @track profilePictureUrl = null;

    // Auto-suggest locations using API
    @track searchKey = '';
    @track suggestions = [];
    
    // Getters for conditional rendering
    get isLoginScreen() { return this.currentScreen === 'login'; }
    get isRegisterScreen() { return this.currentScreen === 'register'; }
    get isDashboardScreen() { return this.currentScreen === 'dashboard'; }
    
    get isSearchActive() { 
        return this.activeTab === 'search' ? 'nav-item active' : 'nav-item'; 
    }
    get isPublishActive() { 
        return this.activeTab === 'publish' ? 'nav-item active' : 'nav-item'; 
    }
    get isRidesActive() { 
        return this.activeTab === 'rides' ? 'nav-item active' : 'nav-item'; 
    }
    get isInboxActive() { 
        return this.activeTab === 'inbox' ? 'nav-item active' : 'nav-item'; 
    }
    get isProfileActive() { 
        return this.activeTab === 'profile' ? 'nav-item active' : 'nav-item'; 
    }
    
    get showSearchTab() { return this.activeTab === 'search'; }
    get showPublishTab() { return this.activeTab === 'publish'; }
    get showRidesTab() { return this.activeTab === 'rides'; }
    get showInboxTab() { return this.activeTab === 'inbox'; }
    get showProfileTab() { return this.activeTab === 'profile'; }
    
    get showNoResults() {
        return this.hasSearched && this.searchResults.length === 0;
    }
    
    get showSearchResults() {
        return this.searchResults.length > 0;
    }
    
    get bookingsTabClass() {
        return this.activeRideSubTab === 'bookings' ? 'ride-tab active' : 'ride-tab';
    }
    
    get publishedTabClass() {
        return this.activeRideSubTab === 'published' ? 'ride-tab active' : 'ride-tab';
    }
    
    get showBookingsSection() {
        return this.activeRideSubTab === 'bookings';
    }
    
    get showPublishedSection() {
        return this.activeRideSubTab === 'published';
    }
    
    get userInitials() {
        return this.currentUser ? this.getInitials(this.currentUser.Name) : '?';
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
    
    // Event Handlers
    handleLoginInputChange(event) {
        const field = event.target.dataset.field;
        this.loginForm[field] = event.target.value;
    }
    
    handleRegisterInputChange(event) {
        const field = event.target.dataset.field;
        this.registerForm[field] = event.target.value;
    }
    
    async handleSearchInputChange(event) {
        const field = event.target.dataset.field;
        const value = event.target.value;
        console.log('Entered Val : ', value);
        this.searchForm[field] = value;

        if (field === 'from') {
            await this.filterFromLocations(value);
        } else if (field === 'to') {
            await this.filterToLocations(value);
        }
    }
    
    async handlePublishInputChange(event) {
        const field = event.target.dataset.field;
        const value = event.target.value;
        this.publishForm[field] = value;

        if (field === 'from') {
            await this.filterFromLocations(value);
        } else if (field === 'to') {
            await this.filterToLocations(value);
        }
    }

    // Get suggested locations from API
    async getSuggestedLocations(value) {
        this.searchKey = value;

        if (this.searchKey.length < 2) {
            return [];
        }

        console.log('Get suggest locations for this text : ', this.searchKey);

        try {
            const result = await search({ query: this.searchKey });
            console.log('Suggested Locations from API :: ', JSON.stringify(result));
            return result; // This is already an array of strings
        } catch (error) {
            console.error('API Error:', error);
            return [];
        }
    }
    
    // Select from suggested locations
    handleSelect(event) {
        const selected = this.suggestions.find(s => s.placeName === event.currentTarget.dataset.name);
        this.searchKey = selected.label;
        this.suggestions = [];
        
        // Optional: fire event with full data
        this.dispatchEvent(new CustomEvent('locationselect', { detail: selected }));
    }

    // Handle suggestion selection
    handleSuggestionSelect(event) {
        const location = event.currentTarget.dataset.location;
        const field = event.currentTarget.dataset.field;
        const form = event.currentTarget.dataset.form;
        
        if (form === 'search') {
            this.searchForm[field] = location;
            if (field === 'from') {
                this.showSearchFromSuggestions = false;
            } else {
                this.showSearchToSuggestions = false;
            }
        } else if (form === 'publish') {
            this.publishForm[field] = location;
            if (field === 'from') {
                this.showPublishFromSuggestions = false;
            } else {
                this.showPublishToSuggestions = false;
            }
        }
    }
    
    // Focus handlers for Search form
    handleSearchFromFocus() {
        this.filterFromLocations(this.searchForm.from);
        this.showSearchFromSuggestions = true;
    }
    
    handleSearchFromBlur() {
        setTimeout(() => {
            this.showSearchFromSuggestions = false;
        }, 200);
    }
    
    handleSearchToFocus() {
        this.filterToLocations(this.searchForm.to);
        this.showSearchToSuggestions = true;
    }
    
    handleSearchToBlur() {
        setTimeout(() => {
            this.showSearchToSuggestions = false;
        }, 200);
    }
    
    // Focus handlers for Publish form
    handlePublishFromFocus() {
        this.filterFromLocations(this.publishForm.from);
        this.showPublishFromSuggestions = true;
    }
    
    handlePublishFromBlur() {
        setTimeout(() => {
            this.showPublishFromSuggestions = false;
        }, 200);
    }
    
    handlePublishToFocus() {
        this.filterToLocations(this.publishForm.to);
        this.showPublishToSuggestions = true;
    }
    
    handlePublishToBlur() {
        setTimeout(() => {
            this.showPublishToSuggestions = false;
        }, 200);
    }
    
    // Filter locations based on input
    async filterFromLocations(inputValue) {
        console.log('inputValue : ', inputValue);
        if (!inputValue || inputValue.trim() === '') {
            this.filteredFromLocations = [...this.allFromLocations];
        } else {
            const searchTerm = inputValue.toLowerCase();

            // First filter from history (these are strings)
            const historyMatches = this.allFromLocations.filter(location =>
                location.toLowerCase().includes(searchTerm)
            );

            console.log('filtered From Locations from history : ', historyMatches);

            // If no matches in history, fetch from API
            if (historyMatches.length === 0) {
                console.log('No From Locations in history, fetching from API...');
                try {
                    const apiResults = await this.getSuggestedLocations(inputValue);
                    console.log('API Results:', apiResults);

                    // IMPORTANT: Create a NEW array reference for reactivity
                    this.filteredFromLocations = [...apiResults];

                    console.log('filteredFromLocations from API :: ', this.filteredFromLocations);
                } catch (error) {
                    console.error('Error fetching suggestions:', error);
                    this.filteredFromLocations = [];
                }
            } else {
                this.filteredFromLocations = historyMatches;
            }
        }
    }
    
    async filterToLocations(inputValue) {
        console.log('inputValue : ', inputValue);
        if (!inputValue || inputValue.trim() === '') {
            this.filteredToLocations = [...this.allToLocations];
        } else {
            const searchTerm = inputValue.toLowerCase();

            // First filter from history (these are strings)
            const historyMatches = this.allToLocations.filter(location =>
                location.toLowerCase().includes(searchTerm)
            );

            console.log('filtered To Locations from history : ', historyMatches);

            // If no matches in history, fetch from API
            if (historyMatches.length === 0) {
                console.log('No To Locations in history, fetching from API...');
                try {
                    const apiResults = await this.getSuggestedLocations(inputValue);
                    console.log('API Results:', apiResults);

                    // IMPORTANT: Create a NEW array reference for reactivity
                    this.filteredToLocations = [...apiResults];

                    console.log('filteredToLocations from API :: ', this.filteredToLocations);
                } catch (error) {
                    console.error('Error fetching suggestions:', error);
                    this.filteredToLocations = [];
                }
            } else {
                this.filteredToLocations = historyMatches;
            }
        }
    }
    
    // Navigation
    goToRegister(event) {
        event.preventDefault();
        this.currentScreen = 'register';
    }
    
    goToLogin(event) {
        event.preventDefault();
        this.currentScreen = 'login';
    }
    
    handleTabClick(event) {
        event.preventDefault();
        const tab = event.currentTarget.dataset.tab;
        if (tab) {
            this.activeTab = tab;
            if (tab === 'rides') {
                this.activeRideSubTab = 'bookings';
            }
        }
    }
    
    handleRideSubTabClick(event) {
        event.preventDefault();
        const subtab = event.currentTarget.dataset.subtab;
        if (subtab) {
            this.activeRideSubTab = subtab;
        }
    }
    
    // Authentication
    async handleLogin() {
        if (!this.loginForm.email || !this.loginForm.password) {
            this.showToast('Error', 'Please fill in all required fields', 'error');
            return;
        }
        
        this.isLoading = true;
        try {
            const result = await loginUser({ 
                email: this.loginForm.email, 
                password: this.loginForm.password 
            });
            
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
    
    // Load location history
    async loadLocationHistory() {
        try {
            const result = await getUserLocationHistory({ userId: this.currentUser.Id });
            
            if (result.success) {
                this.allFromLocations = result.fromLocations || [];
                this.allToLocations = result.toLocations || [];
                this.filteredFromLocations = [...this.allFromLocations];
                this.filteredToLocations = [...this.allToLocations];
            }
        } catch (error) {
            console.error('Failed to load location history:', error);
            this.allFromLocations = [];
            this.allToLocations = [];
            this.filteredFromLocations = [];
            this.filteredToLocations = [];
        }
    }
    
    // Search functionality
    async handleSearchRides() {
        if (!this.searchForm.from || !this.searchForm.to || !this.searchForm.date) {
            this.showToast('Error', 'Please fill in all search criteria', 'error');
            return;
        }
        console.log('searchForm.from: ', this.searchForm.from)
        console.log('searchForm.to: ', this.searchForm.to)
        
        this.isLoading = true;
        this.hasSearched = true;
        try {
            this.searchResults = await searchRides({
                fromLocation: this.searchForm.from,
                toLocation: this.searchForm.to,
                travelDate: this.searchForm.date,
                passengers: parseInt(this.searchForm.passengers)
            });
            console.log('search Resultss: ', JSON.stringify(this.searchResults))
            
            if (this.searchResults.length === 0) {
                this.showToast('Info', 'No rides found for your search criteria', 'info');
            }
        } catch (error) {
            this.showToast('Error', 'Search failed: ' + error.body.message, 'error');
        } finally {
            this.isLoading = false;
        }
    }
    
    // Publish ride functionality
    async handlePublishRide() {
        if (!this.publishForm.from || !this.publishForm.to || !this.publishForm.date || 
            !this.publishForm.time || !this.publishForm.price || !this.publishForm.vehicleType) {
            this.showToast('Error', 'Please fill in all required fields', 'error');
            return;
        }
        
        this.isLoading = true;
        try {
            const departureDateTime = new Date(this.publishForm.date + 'T' + this.publishForm.time);
            
            const result = await publishRide({
                userId: this.currentUser.Id,
                fromLocation: this.publishForm.from,
                toLocation: this.publishForm.to,
                departureDateTime: departureDateTime,
                availableSeats: parseInt(this.publishForm.seats),
                pricePerSeat: parseFloat(this.publishForm.price),
                vehicleType: this.publishForm.vehicleType,
                notes: this.publishForm.notes
            });
            console.log('Publish ride result: ', JSON.stringify(result));
            if (result.success) {
                this.showToast('Success', result.message, 'success');
                this.resetPublishForm();
                //await this.loadUserRides();
                this.userRides = await refreshUserPublishedRides({ userId: this.currentUser.Id });
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
    
    // Book ride functionality
    async handleBookRide(event) {
        const rideId = event.target.dataset.rideid;
        
        this.isLoading = true;
        try {
            const result = await bookRide({
                rideId: rideId,
                passengerId: this.currentUser.Id,
                seatsBooked: 1
            });
            
            if (result.success) {
                this.showToast('Success', result.message, 'success');
                await this.loadUserBookings();
                await this.loadLocationHistory();
                this.handleSearchRides();
            } else {
                this.showToast('Error', result.message, 'error');
            }
        } catch (error) {
            this.showToast('Error', 'Booking failed: ' + error.body.message, 'error');
        } finally {
            this.isLoading = false;
        }
    }
    
    // Modal Handlers - Booking
    async handleBookingClick(event) {
        const bookingId = event.currentTarget.dataset.bookingid;
        this.isLoading = true;
        
        try {
            const booking = await getBookingDetails({ bookingId: bookingId });
            this.selectedBooking = booking;
            
            const departureDateTime = new Date(booking.Ride__r.Departure_DateTime__c);
            this.editBookingForm = {
                date: this.formatDate(departureDateTime),
                time: this.formatTime(departureDateTime),
                seatsBooked: booking.Seats_Booked__c
            };
            
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
        this.editBookingForm = { date: '', time: '', seatsBooked: 1 };
    }
    
    handleBookingEditChange(event) {
        const field = event.target.dataset.field;
        this.editBookingForm[field] = event.target.value;
    }
    
    async handleSaveBooking() {
        this.isLoading = true;
        
        try {
            const departureDateTime = new Date(this.editBookingForm.date + 'T' + this.editBookingForm.time);
            
            const result = await updateBooking({
                bookingId: this.selectedBooking.Id,
                departureDateTime: departureDateTime,
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
        if (!confirm('Are you sure you want to cancel this booking?')) {
            return;
        }
        
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
    
    // Modal Handlers - Ride
    async handleRideClick(event) {
        const rideId = event.currentTarget.dataset.rideid;
        this.isLoading = true;
        
        try {
            const ride = await getRideDetails({ rideId: rideId });
            this.selectedRide = ride;
            
            const departureDateTime = new Date(ride.Departure_DateTime__c);
            this.editRideForm = {
                date: this.formatDate(departureDateTime),
                time: this.formatTime(departureDateTime),
                availableSeats: ride.Available_Seats__c,
                pricePerSeat: ride.Price_Per_Seat__c,
                vehicleType: ride.Vehicle_Type__c,
                notes: ride.Notes__c || ''
            };
            
            this.ridePassengers = (ride.Bookings__r || []).map(booking => ({
                ...booking,
                initials: this.getInitials(booking.Passenger__r.Name)
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
        const field = event.target.dataset.field;
        this.editRideForm[field] = event.target.value;
    }
    
    async handleSaveRide() {
        this.isLoading = true;
        
        try {
            const departureDateTime = new Date(this.editRideForm.date + 'T' + this.editRideForm.time);
            
            const result = await updateRide({
                rideId: this.selectedRide.Id,
                departureDateTime: departureDateTime,
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
        if (!confirm('Are you sure you want to delete this ride? This action cannot be undone.')) {
            return;
        }
        
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
    
    // Data loading
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
    
    // Profile Picture Methods
    async loadProfilePicture() {
        try {
            const result = await getProfilePictureNonCacheable({ userId: this.currentUser.Id });
            this.profilePictureUrl = result.success ? result.pictureUrl : null;
            console.log('Profile picture loaded:', this.profilePictureUrl);
        } catch (error) {
            console.error('Failed to load profile picture:', error);
            this.profilePictureUrl = null;
        }
    }
    
    handleProfilePictureUpload(event) {
        const file = event.target.files[0];
        
        if (!file) {
            return;
        }
        
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
                    // Reload profile picture immediately without page refresh
                    await this.loadProfilePicture();
                } else {
                    this.showToast('Error', result.message, 'error');
                }
            } catch (error) {
                console.error('Upload error:', error);
                this.showToast('Error', 'Failed to upload profile picture: ' + (error.body ? error.body.message : error.message), 'error');
            } finally {
                this.isLoading = false;
                event.target.value = '';
            }
        };
        
        reader.onerror = () => {
            this.showToast('Error', 'Failed to read the file', 'error');
            this.isLoading = false;
        };
        
        reader.readAsDataURL(file);
    }
    
    async handleDeleteProfilePicture() {
        if (!confirm('Are you sure you want to delete your profile picture?')) {
            return;
        }
        
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
            console.error('Delete error:', error);
            this.showToast('Error', 'Failed to delete profile picture: ' + (error.body ? error.body.message : error.message), 'error');
        } finally {
            this.isLoading = false;
        }
    }
    
    // Utility methods
    formatDate(date) {
        const year = date.getFullYear();
        const month = String(date.getMonth() + 1).padStart(2, '0');
        const day = String(date.getDate()).padStart(2, '0');
        return `${year}-${month}-${day}`;
    }
    
    formatTime(date) {
        const hours = String(date.getHours()).padStart(2, '0');
        const minutes = String(date.getMinutes()).padStart(2, '0');
        return `${hours}:${minutes}`;
    }
    
    getInitials(name) {
        if (!name) return '?';
        const parts = name.trim().split(' ');
        if (parts.length === 1) return parts[0].charAt(0).toUpperCase();
        return (parts[0].charAt(0) + parts[parts.length - 1].charAt(0)).toUpperCase();
    }
    
    resetForms() {
        this.loginForm = { email: '', password: '' };
        this.registerForm = { name: '', email: '', phone: '', password: '', dateOfBirth: '', gender: '' };
    }
    
    resetPublishForm() {
        this.publishForm = { from: '', to: '', date: '', time: '', seats: 1, price: '', vehicleType: '', notes: '' };
    }
    
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
        
        this.showToast('Success', 'Logged out successfully', 'success');
    }
    
    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        }));
    }
}