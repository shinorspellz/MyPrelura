//
//  Localization.swift
//  Prelura-swift
//
//  In-app language: English (en) or Greek (el). When "el" is selected, UI strings use Greek.
//

import Foundation

/// UserDefaults key for selected app language: "en" | "el"
let kAppLanguage = "app_language"

/// Valid app language codes. Stored value is normalized to one of these to avoid crashes when device language or storage changes.
private let kValidAppLanguages = ["en", "el"]

enum L10n {

    /// Returns the localized string for the current app language. English uses the key as text; Greek uses translations.
    static func string(_ key: String) -> String {
        let lang = validatedAppLanguage()
        if lang == "el" {
            return greek[key] ?? key
        }
        return key
    }

    /// Current language code for conditional logic if needed. Always "en" or "el".
    static var currentLanguage: String {
        validatedAppLanguage()
    }

    /// Returns stored app language if valid; otherwise "en". Persists correction to avoid repeat crashes after device language change.
    static func validatedAppLanguage() -> String {
        let raw = UserDefaults.standard.string(forKey: kAppLanguage) ?? "en"
        if kValidAppLanguages.contains(raw) { return raw }
        UserDefaults.standard.set("en", forKey: kAppLanguage)
        return "en"
    }

    static var isGreek: Bool { currentLanguage == "el" }

    private static let greek: [String: String] = [
        // Tab bar
        "Home": "Αρχική",
        "Discover": "Ανακάλυψη",
        "Sell": "Πώληση",
        "Inbox": "Εισερχόμενα",
        "Profile": "Προφίλ",
        "Options": "Επιλογές",
        "Edit listing": "Επεξεργασία αγγελίας",
        "Share": "Κοινοποίηση",
        "Mark as sold": "Σημείωση ως πωλημένο",
        "Sold": "Πωλήθηκε",
        "Delete listing": "Διαγραφή αγγελίας",
        "Copy to a new listing": "Αντιγραφή σε νέα αγγελία",
        "Report listing": "Αναφορά αγγελίας",
        "Copy link": "Αντιγραφή συνδέσμου",
        "Error": "Σφάλμα",
        "Delete listing?": "Διαγραφή αγγελίας;",
        "Mark as sold?": "Σημείωση ως πωλημένο;",

        // Menu – profile drawer
        "Shop Value": "Αξία Καταστήματος",
        "Dashboard": "Πίνακας Ελέγχου",
        "Seller dashboard": "Πίνακας πωλητή",
        "Shop Categories": "Κατηγορίες Καταστήματος",
        "Orders": "Παραγγελίες",
        "Order details": "Λεπτομέρειες παραγγελίας",
        "Select item": "Επιλογή προϊόντος",
        "Which item is your issue about? Choose one to continue.": "Ποιο προϊόν αφορά το πρόβλημά σας; Επιλέξτε ένα για να συνεχίσετε.",
        "Favourites": "Αγαπημένα",
        "Shop tools": "Εργαλεία Καταστήματος",
        "Background replacer": "Αντικατάσταση Φόντου",
        "Multi-buy discounts": "Εκπτώσεις πολλαπλών αγορών",
        "Multi-buy discount (%d%%)": "Εκπτωση πολλαπλών αγορών (%d%%)",
        "On": "Ενεργό",
        "Off": "Ανενεργό",
        "Vacation Mode": "Λειτουργία Αργίας",
        "Invite Friend": "Προσκάλεσε Φίλο",
        "Help Centre": "Κέντρο Βοήθειας",
        "About Prelura": "Σχετικά με το Prelura",
        "Admin Dashboard": "Πίνακας Διαχείρισης",
        "Settings": "Ρυθμίσεις",
        "Logout": "Αποσύνδεση",

        // Settings
        "Account Settings": "Ρυθμίσεις Λογαριασμού",
        "Currency": "Νόμισμα",
        "Privacy": "Απόρρητο",
        "Shipping Address": "Διεύθυνση Αποστολής",
        "Appearance": "Εμφάνιση",
        "Profile details": "Στοιχεία προφίλ",
        "Payments": "Πληρωμές",
        "Postage": "Ταχυδρομικά",
        "Security & Privacy": "Ασφάλεια και απόρρητο",
        "Identity verification": "Επαλήθευση ταυτότητας",
        "Admin Actions": "Ενέργειες διαχειριστή",
        "Notifications": "Ειδοποιήσεις",
        "Push notifications": "Ειδοποιήσεις push",
        "Email notifications": "Ειδοποιήσεις email",
        "Log out": "Αποσύνδεση",
        "Cancel": "Ακύρωση",
        "Confirm": "Επιβεβαίωση",
        "Are you sure you want to logout?": "Είστε σίγουροι ότι θέλετε να αποσυνδεθείτε;",

        // Appearance
        "Theme": "Θέμα",
        "Use System Settings": "Χρήση ρυθμίσεων συστήματος",
        "Light": "Φωτεινή",
        "Dark": "Σκούρα",
        "Light and Dark apply to all screens, components, and elements. System follows your device setting.": "Φωτεινή και σκούρα ισχύουν σε όλες τις οθόνες. Το σύστημα ακολουθεί τη ρύθμιση της συσκευής σας.",
        "Your app's language": "Γλώσσα εφαρμογής",
        "Language": "Γλώσσα",
        "Language updated": "Η γλώσσα ενημερώθηκε",
        "The app will use the selected language the next time you open it. Close and reopen the app to see the change.": "Η εφαρμογή θα χρησιμοποιήσει την επιλεγμένη γλώσσα την επόμενη φορά που θα την ανοίξετε. Κλείστε και ανοίξτε ξανά την εφαρμογή για να δείτε την αλλαγή.",
        "English": "Αγγλικά",
        "Greek": "Ελληνικά",
        "Greek displays the app in Greek.": "Η γλώσσα Ελληνικά εμφανίζει την εφαρμογή στα Ελληνικά.",

        // About Prelura
        "How to use Prelura": "Πώς να χρησιμοποιήσετε το Prelura",
        "Legal Information": "Νομικές πληροφορίες",

        // Help Centre
        "Got a burning question?": "Έχετε κάποια ερώτηση;",
        "Frequently asked": "Συχνές ερωτήσεις",
        "More topics": "Περισσότερα θέματα",
        "How can I cancel an existing order": "Πώς μπορώ να ακυρώσω μια υπάρχουσα παραγγελία",
        "How long does a refund normally take?": "Πόσο διαρκεί συνήθως η επιστροφή χρημάτων;",
        "When will I receive my item?": "Πότε θα λάβω το προϊόν μου;",
        "How will I know if my order has been shipped?": "Πώς θα μάθω αν η παραγγελία μου έχει σταλεί;",
        "What's a collection point?": "Τι είναι το σημείο παραλαβής;",
        "Item says \"Delivered\" but I don't have it": "Γράφει \"Παραδόθηκε\" αλλά δεν το έχω λάβει",
        "What's Vacation mode?": "Τι είναι η λειτουργία αργίας;",
        "How do I earn a trusted seller badge?": "Πώς κερδίζω το σήμα αξιόπιστου πωλητή;",
        "No matching topics": "Δεν βρέθηκαν σχετικά θέματα",
        "Start a conversation": "Ξεκινήστε συνομιλία",
        "e.g. How do I change my profile photo?": "π.χ. Πώς αλλάζω τη φωτογραφία προφίλ μου;",

        // Menu (navigation)
        "Menu": "Μενού",
        "© Prelura 2026": "© Prelura 2026",
        "© Voltis Labs 2026": "© Voltis Labs 2026",
        "Debug": "Εντοπισμός σφαλμάτων",

        // Home
        "Search items, brands or styles": "Αναζήτηση προϊόντων, εμπορικών σημάτων ή στυλ",
        "All": "Όλα",
        "Women": "Γυναίκες",
        "Men": "Άνδρες",
        "Kids": "Παιδικά",
        "Toddlers": "Νήπια",
        "Girls": "Κορίτσια",
        "Boys": "Αγόρια",

        // Discover
        "Search members": "Αναζήτηση μελών",
        "Search conversations": "Αναζήτηση συνομιλιών",
        "Shop by style": "Επίλεξε στυλ",
        "Explore by style": "Εξερεύνηση ανά στυλ",
        "Feed": "Ροή",
        "Explore communities": "Εξερεύνησε κοινότητες",
        "See all": "Όλα",
        "Get inspired": "Εμπνεύσου",

        // Browse
        "Browse": "Περιήγηση",
        "Sort: ": "Ταξινόμηση: ",
        "No items found": "Δεν βρέθηκαν προϊόντα",
        "Try adjusting your filters": "Δοκιμάστε να αλλάξετε τα φίλτρα",
        "No products found": "Δεν βρέθηκαν προϊόντα",

        // Favourites (Favourites key in Menu section)
        "No favourites yet": "Δεν υπάρχουν αγαπημένα ακόμα",
        "Items you save as favourites will appear here.": "Τα προϊόντα που αποθηκεύετε ως αγαπημένα θα εμφανίζονται εδώ.",
        "No results for \"%@\"": "Δεν βρέθηκαν αποτελέσματα για «%@»",
        "Search favourites": "Αναζήτηση αγαπημένων",

        // Profile (Favourites used from Menu section)
        "Listings": "Αγγελίες",
        "Listing": "Αγγελία",
        "No listings yet": "Δεν υπάρχουν αγγελίες ακόμα",
        "No items match your filters": "Δεν βρέθηκαν προϊόντα με τα φίλτρα σας",
        "Followings": "Ακόλουθοι",
        "Following": "Ακόλουθοι",
        "Followers": "Οπαδοί",
        "Follower": "Οπαδός",
        "Reviews": "Κριτικές",
        "Location": "Τοποθεσία",
        "N/A": "Μ/Δ",
        "Categories": "Κατηγορίες",
        "item": "προϊόν",
        "items": "προϊόντα",
        "Multi-buy:": "Πολλαπλές αγορές:",
        "View cart": "Δείτε καλάθι",
        "View bag": "Δείτε τσάντα",
        "Shopping bag": "Τσάντα αγορών",
        "Your bag is empty": "Η τσάντα σας είναι άδεια",
        "Add to bag": "Προσθήκη στην τσάντα",
        "Checkout": "Ολοκλήρωση αγοράς",
        "Top brands": "Κορυφαίες μάρκες",
        "Filter": "Φίλτρο",
        "Clear": "Καθαρισμός",
        "Sort": "Ταξινόμηση",
        "Done": "ΟΚ",
        "Condition": "Κατάσταση",
        "Price": "Τιμή",
        "OK": "ΟΚ",

        // Auth
        "Welcome back": "Καλώς ήρθατε πάλι",
        "Username": "Όνομα χρήστη",
        "Enter your username": "Εισάγετε το όνομα χρήστη σας",
        "Password": "Κωδικός",
        "Enter your password": "Εισάγετε τον κωδικό σας",
        "Forgot password?": "Ξεχάσατε τον κωδικό;",
        "Don't have an account?": "Δεν έχετε λογαριασμό;",
        "Sign up": "Εγγραφή",
        "Login": "Σύνδεση",
        "Continue as guest": "Συνέχεια ως επισκέπτης",
        "You're browsing as guest": "Περιηγείστε ως επισκέπτης",
        "Sign in to see your profile, listings and messages.": "Συνδεθείτε για να δείτε το προφίλ σας, τις αγγελίες και τα μηνύματά σας.",
        "Sign in": "Σύνδεση",

        // Profile sort
        "Relevance": "Συσχέτιση",
        "Newest First": "Νεότερα πρώτα",
        "Price Ascending": "Τιμή αύξουσα",
        "Price Descending": "Τιμή φθίνουσα",
        "Price range": "Εύρος τιμών",
        "Excellent Condition": "Εξαιρετική κατάσταση",
        "Good Condition": "Καλή κατάσταση",
        "Brand New With Tags": "Καινό με ετικέτες",
        "Brand new Without Tags": "Καινό χωρίς ετικέτες",
        "Heavily Used": "Έντονα χρησιμοποιημένο",
        "Apply": "Εφαρμογή",
        "Min. Price": "Ελάχ. τιμή",
        "Max. Price": "Μέγ. τιμή",

        // Sell
        "Sell an item": "Πώληση προϊόντος",
        "Close": "Κλείσιμο",
        "Upload": "Μεταφόρτωση",
        "Upload from drafts": "Μεταφόρτωση από πρόχειρα",
        "Save draft": "Αποθήκευση πρόχειρου",
        "Drafts": "Πρόχειρα",
        "Select drafts": "Επιλογή προχείρων",
        "Untitled draft": "Πρόχειρο χωρίς τίτλο",
        "Draft saved": "Το πρόχειρο αποθηκεύτηκε",
        "Your listing has been saved as a draft. Open it from \"Upload from drafts\".": "Η καταχώρισή σας αποθηκεύτηκε ως πρόχειρο. Ανοίξτε το από \"Μεταφόρτωση από πρόχειρα\".",
        "Add up to 20 photos": "Προσθήκη έως 20 φωτογραφιών",
        "Add photo": "Προσθήκη φωτογραφίας",
        "Suggest from title": "Πρόταση από τίτλο",
        "Suggest from photo": "Πρόταση από φωτογραφία",
        "Tap to select photos from your gallery": "Αγγίξτε για να επιλέξετε φωτογραφίες από τη συλλογή σας",
        "Item Details": "Στοιχεία προϊόντος",
        "Item Information": "Πληροφορίες προϊόντος",
        "Category": "Κατηγορία",
        "Brand": "Μάρκα",
        "Colours": "Χρώματα",
        "Colour": "Χρώμα",
        "Additional Details": "Επιπλέον στοιχεία",
        "Measurements (Optional)": "Διαστάσεις (προαιρετικό)",
        "Material (Optional)": "Υλικό (προαιρετικό)",
        "Style (Optional)": "Στυλ (προαιρετικό)",
        "Pricing & Shipping": "Τιμή και αποστολή",
        "Discount Price (Optional)": "Εκπτωτική τιμή (προαιρετικό)",
        "Parcel Size": "Μέγεθος δέματος",
        "The buyer always pays for postage.": "Ο αγοραστής πληρώνει πάντα την αποστολή.",
        "Select Category": "Επιλογή κατηγορίας",
        "Search categories": "Αναζήτηση κατηγοριών",
        "Search shop": "Αναζήτηση καταστήματος",
        "No categories found": "Δεν βρέθηκαν κατηγορίες",
        "Select": "Επιλογή",
        "Selected": "Επιλεγμένο",
        "Select Condition": "Επιλογή κατάστασης",
        "Select Colours": "Επιλογή χρωμάτων",
        "Measurements": "Διαστάσεις",
        "Add measurements like chest, waist, length": "Προσθέστε διαστάσεις π.χ. στήθος, μέση, μήκος",
        "Label": "Ετικέτα",
        "Value": "Τιμή",
        "Add measurement": "Προσθήκη μέτρησης",
        "Custom…": "Προσαρμογή…",
        "Select Material": "Επιλογή υλικού",
        "Select Style": "Επιλογή στυλ",
        "Find a style": "Βρείτε στυλ",
        "Discount: %d%%": "Έκπτωση: %d%%",
        "Please set the price first": "Ορίστε πρώτα την τιμή",
        "Discount Price": "Εκπτωτική τιμή",
        "Sale price": "Τιμή πώλησης",
        "Amount off": "Ποσό έκπτωσης",
        "Optional. Enter the discounted price; the discount % is calculated from the main price.": "Προαιρετικό. Εισάγετε την εκπτωτική τιμή· το % έκπτωσης υπολογίζεται από την κύρια τιμή.",
        "Enter the amount to take off the price (e.g. 13 for £13 off).": "Εισάγετε το ποσό που αφαιρείται από την τιμή (π.χ. 13 για 13 £ έκπτωση).",
        "Listed price": "Τιμή καταλόγου",
        "Final price": "Τελική τιμή",
        "Discount (%)": "Έκπτωση (%)",
        "Edit discount % or sale price; both stay in sync.": "Επεξεργαστείτε % έκπτωσης ή τιμή πώλησης· συγχρονίζονται μεταξύ τους.",
        "Loading brands...": "Φόρτωση μαρκών...",
        "Loading more...": "Φόρτωση περισσότερων...",
        "No brands match your search.": "Δεν βρέθηκαν μάρκες που ταιριάζουν με την αναζήτησή σας.",
        "Try Cart": "Δοκιμαστικό καλάθι",
        "One bag, many sellers": "Ένα καλάθι, πολλοί πωλητές",
        "Try Cart lets you add pieces from different shops into a single bag. Keep browsing—your picks stay with you everywhere on Prelura.": "Το Δοκιμαστικό καλάθι σάς επιτρέπει να προσθέτετε κομμάτια από διαφορετικά καταστήματα σε ένα καλάθι. Συνεχίστε την περιήγηση—οι επιλογές σας μένουν μαζί σας παντού στο Prelura.",
        "Save time on every haul": "Εξοικονομήστε χρόνο σε κάθε αγορά",
        "No more jumping seller by seller. Search, tap the bag, and build your haul in one flow—with a running total so you always know where you stand.": "Χωρίς άλματα από πωλητή σε πωλητή. Αναζητήστε, πατήστε το καλάθι και χτίστε την αγορά σας σε μία ροή—με τρέχον σύνολο ώστε να ξέρετε πάντα πού βρίσκεστε.",
        "Shop smarter, checkout clearer": "Ψωνίστε πιο έξυπνα, ταμείο πιο καθαρά",
        "Use Try Cart from Shop All and favourites. Mix brands freely, review your bag anytime, then check out when you are ready—on your terms.": "Χρησιμοποιήστε το Δοκιμαστικό καλάθι από το Shop All και τα αγαπημένα. Αναμείξτε μάρκες ελεύθερα, δείτε το καλάθι σας όποτε θέλετε και ολοκληρώστε όταν είστε έτοιμοι—με τους δικούς σας όρους.",
        "Next": "Επόμενο",
        "Start shopping": "Ξεκινήστε τις αγορές",
        "Skip": "Παράλειψη",
        "Shop All": "Όλα τα προϊόντα",
        "Enter brand name": "Εισάγετε όνομα μάρκας",
        "Tip: similar price range is recommended based on similar items sold on Prelura.": "Συμβουλή: συνιστάται παρόμοιο εύρος τιμών με βάση παρόμοια αντικείμενα που πωλήθηκαν στο Prelura.",
        "Similar sold items": "Παρόμοια πωλημένα αντικείμενα",

        // Discover
        "Recently viewed": "Πρόσφατα προβεβλημένα",
        "See All": "Δείτε όλα",
        "Results": "Αποτελέσματα",
        "Brands You Love": "Οι αγαπημένες σας μάρκες",
        "Recommended from your favorite brands": "Προτεινόμενα από τις αγαπημένες σας μάρκες",
        "Top Shops": "Κορυφαία καταστήματα",
        "Buy from trusted and popular vendors": "Αγοράστε από αξιόπιστους και δημοφιλείς πωλητές",
        "Shop Bargains": "Προσφορές",
        "Steals under £15": "Ευκαιρίες κάτω από 15 £",
        "On Sale": "Προσφορά",
        "Discounted items": "Προϊόντα με έκπτωση",

        // Notifications & Chat
        "No notifications": "Δεν υπάρχουν ειδοποιήσεις",
        "Messages": "Μηνύματα",
        "Type a message...": "Πληκτρολογήστε μήνυμα...",
        "Thinking...": "Σκέφτομαι...",
        "Welcome to the chat, I'm Lenny, and I'm here to assist you. Send a message to get started.": "Καλώς ήρθατε στη συνομιλία, είμαι ο Lenny και είμαι εδώ για να σας βοηθήσω. Στείλτε ένα μήνυμα για να ξεκινήσετε.",
        "Hi! What are you looking for? Try something like a dress, jacket, or shoes.": "Γεια! Τι ψάχνετε; Δοκιμάστε π.χ. φόρεμα, ζακέτα ή παπούτσια.",
        "Hello! I can help you find something. Try asking for a colour and item, like red dress or blue shoes.": "Γεια σας! Μπορώ να σας βοηθήσω να βρείτε κάτι. Ζητήστε χρώμα και είδος, π.χ. κόκκινο φόρεμα ή μπλε παπούτσια.",
        "Hey! What would you like to find? For example: black jacket, white trainers, or a green dress.": "Γεια! Τι θα θέλατε να βρείτε; Π.χ. μαύρη ζακέτα, λευκά παπούτσια ή πράσινο φόρεμα.",
        "Hi there! I'm here to help you shop. Try something like navy blazer or pink skirt.": "Γεια σας! Είμαι εδώ για να σας βοηθήσω να ψωνίσετε. Δοκιμάστε π.χ. μπλε μπλεζέ ή ροζ φούστα.",
        "I'm good, thanks! What can I help you find today? Try a colour and item, like red dress or blue shoes.": "Καλά είμαι, ευχαριστώ! Τι μπορώ να σας βρω σήμερα; Δοκιμάστε χρώμα και είδος, π.χ. κόκκινο φόρεμα ή μπλε παπούτσια.",
        "Doing great! What are you looking for? I can help you find dresses, jackets, shoes, and more.": "Τέλεια! Τι ψάχνετε; Μπορώ να βρω φορέματα, ζακέτες, παπούτσια και άλλα.",
        "All good here! What would you like to browse? Try something like green hoodie or beige coat.": "Όλα καλά! Τι θα θέλατε να δείτε; Δοκιμάστε π.χ. πράσινο κοντομάνικο ή μπεζ παλτό.",
        "I'm doing well, thanks for asking! What can I find for you? For example: black jacket or white trainers.": "Καλά είμαι, ευχαριστώ που ρωτήσατε! Τι μπορώ να σας βρω; Π.χ. μαύρη ζακέτα ή λευκά παπούτσια.",
        "Good, thanks! How can I help you shop today? Try asking for an item and colour.": "Καλά, ευχαριστώ! Πώς μπορώ να σας βοηθήσω να ψωνίσετε σήμερα; Ζητήστε ένα είδος και χρώμα.",
        "I don't understand that. I can help you find items by colour, category, or style—try something like \"red dress\" or \"blue shoes\".": "Δεν το καταλαβαίνω. Μπορώ να βοηθήσω να βρείτε προϊόντα κατά χρώμα, κατηγορία ή στυλ—δοκιμάστε π.χ. «κόκκινο φόρεμα» ή «μπλε παπούτσια».",
        "I'm not sure about that. I'm best at finding clothes and accessories—try something like pink skirt or navy blazer.": "Δεν είμαι σίγουρος. Γνωρίζω καλύτερα ρούχα και αξεσουάρ—δοκιμάστε π.χ. ροζ φούστα ή μπλε μπλεζέ.",
        "That's outside what I can help with. I can search for items by colour and type—e.g. green hoodie or beige coat.": "Αυτό δεν μπορώ να το βοηθήσω. Μπορώ να ψάξω προϊόντα κατά χρώμα και είδος—π.χ. πράσινο κοντομάνικο ή μπεζ παλτό.",
        "We don't have size %@ in these results, but here are some options you might like.": "Δεν έχουμε μέγεθος %@ σε αυτά τα αποτελέσματα, αλλά ορίστε μερικές επιλογές που μπορεί να σας αρέσουν.",

        // Auth (extra)
        "Create Account": "Δημιουργία λογαριασμού",
        "Join Prelura today": "Γίνε μέλος του Prelura σήμερα",
        "Email": "Email",
        "First Name": "Όνομα",
        "Last Name": "Επώνυμο",
        "Confirm Password": "Επιβεβαίωση κωδικού",
        "Forgot Password": "Ξεχάσατε τον κωδικό;",
        "Enter the email address associated with your account and we'll send you a link to reset your password.": "Εισάγετε το email του λογαριασμού σας και θα σας στείλουμε σύνδεσμο για επαναφορά κωδικού.",
        "Check your email": "Ελέγξτε το email σας",
        "We've sent a 6-digit code to %@. Enter it on the next screen to set a new password.": "Στείλαμε 6ψήφιο κωδικό στο %@. Εισάγετέ τον στην επόμενη οθόνη για νέο κωδικό.",
        "Enter code": "Εισάγετε κωδικό",
        "Send reset link": "Αποστολή συνδέσμου επαναφοράς",
        "Enter your email": "Εισάγετε το email σας",

        // Item detail
        "Member's items": "Προϊόντα μέλους",
        "Similar items": "Παρόμοια προϊόντα",
        "Shop bundles": "Αγορές σε πακέτα",
        "Save on postage": "Εξοικονομήστε στην αποστολή",
        "No member items available yet": "Δεν υπάρχουν ακόμα προϊόντα μέλους",
        "No similar items available yet": "Δεν υπάρχουν ακόμα παρόμοια προϊόντα",
        "Your offer": "Η προσφορά σας",
        "Message (optional)": "Μήνυμα (προαιρετικό)",
        "Send an offer": "Αποστολή προσφοράς",

        // Vacation mode
        "Note: Turning on vacation will hide your items from all catalogues": "Σημείωση: Η ενεργοποίηση της λειτουργίας αργίας θα αποκρύψει τα προϊόντα σας από όλους τους καταλόγους",

        // Shop value
        "Current shop value": "Τρέχουσα αξία καταστήματος",
        "active listings": "ενεργές αγγελίες",
        "Balance": "Υπόλοιπο",
        "Pending %@": "Εκκρεμεί %@",
        "This month": "Αυτό το μήνα",
        "Total earnings": "Συνολικά κέρδη",
        "Lifetime": "Συνολικά (πάντα)",
        "transactions completed": "ολοκληρωμένες συναλλαγές",
        "Transactions completed": "Ολοκληρωμένες συναλλαγές",
        "Help": "Βοήθεια",
        "Status": "Κατάσταση",
        "Seller": "Πωλητής",
        "Buyer": "Αγοραστής",
        "Other party": "Άλλο μέρος",
        "Items": "Προϊόντα",
        "Summary": "Σύνοψη",
        "Total": "Σύνολο",
        "Pending orders": "Εκκρεμείς παραγγελίες",
        "Earnings & balance": "Κέρδη και υπόλοιπο",
        "Withdraw": "Ανάληψη",
        "Back": "Πίσω",
        "Continue": "Συνέχεια",
        "Bank details": "Τραπεζικά στοιχεία",
        "Review withdrawal": "Επιβεβαίωση ανάληψης",
        "How much would you like to withdraw?": "Πόσο θέλετε να αναλήψετε;",
        "Available balance": "Διαθέσιμο υπόλοιπο",
        "Amount cannot exceed available balance.": "Το ποσό δεν μπορεί να υπερβαίνει το διαθέσιμο υπόλοιπο.",
        "Withdrawal requested": "Ανάληψη ζητήθηκε",
        "Your withdrawal of %@ will usually reach your bank within 30 minutes.": "Η ανάληψή σας %@ συνήθως φτάνει στην τράπεζά σας εντός 30 λεπτών.",
        "Withdrawing to account ending in %@": "Ανάληψη σε λογαριασμό που τελειώνει σε %@",
        "You'll add your bank details on the next step.": "Θα προσθέσετε τα τραπεζικά σας στοιχεία στο επόμενο βήμα.",
        "Withdrawals usually reach your bank within 30 minutes.": "Οι αναλήψεις συνήθως φτάνουν στην τράπεζά σας εντός 30 λεπτών.",
        "Account holder": "Δικαιούχος λογαριασμού",
        "Confirm your withdrawal": "Επιβεβαιώστε την ανάληψή σας",
        "Enter your UK bank details. Withdrawals usually reach your bank within 30 minutes.": "Εισάγετε τα στοιχεία της βρετανικής τράπεζάς σας. Οι αναλήψεις συνήθως φτάνουν στην τράπεζά σας εντός 30 λεπτών.",
        "Buyer protection fee": "Τέλος προστασίας αγοραστή",
        "Card ending in %@": "Κάρτα που τελειώνει σε %@",
        "No payment method added": "Δεν προστέθηκε μέθοδος πληρωμής",
        "Add payment method": "Προσθήκη μεθόδου πληρωμής",
        "Payment": "Πληρωμή",
        "This is a secure encryption payment": "Αυτή είναι ασφαλής κρυπτογραφημένη πληρωμή",

        // Reviews
        "No reviews yet": "Δεν υπάρχουν ακόμα κριτικές",
        "Member reviews (%@)": "Κριτικές μελών (%@)",
        "Automatic reviews (0)": "Αυτόματες κριτικές (0)",
        "How reviews work": "Πώς λειτουργούν οι κριτικές",

        // Followers / Following (Following key already in Profile section)
        "No followers yet": "Δεν υπάρχουν ακόμα οπαδοί",
        "Not following anyone yet": "Δεν ακολουθείτε ακόμα κανέναν",

        // Settings (extended)
        "Saved": "Αποθηκεύτηκε",
        "Your postage settings have been saved.": "Οι ρυθμίσεις αποστολής σας αποθηκεύτηκαν.",
        "Your bank account has been saved. Payouts will be sent here when delivery is complete and the customer is happy.": "Ο τραπεζικός σας λογαριασμός αποθηκεύτηκε. Οι πληρωμές θα σταλούν εδώ όταν η παράδοση ολοκληρωθεί και ο πελάτης είναι ικανοποιημένος.",
        "Unlock your account": "Ξεκλειδώστε τον λογαριασμό σας",
        "Verify your identity to access all features and build trust with buyers.": "Επαληθεύστε την ταυτότητά σας για πρόσβαση σε όλες τις λειτουργίες και να δημιουργήσετε εμπιστοσύνη με αγοραστές.",
        "Current Password": "Τρέχων κωδικός",
        "New Password": "Νέος κωδικός",
        "Confirm New Password": "Επιβεβαίωση νέου κωδικού",
        "Passwords do not match": "Οι κωδικοί δεν ταιριάζουν",
        "Reset Password": "Επαναφορά κωδικού",
        "Your password has been changed successfully.": "Ο κωδικός σας άλλαξε με επιτυχία.",
        "Pausing your account will hide your profile and listings. You can reactivate later by logging in.": "Η παύση του λογαριασμού θα αποκρύψει το προφίλ και τις αγγελίες σας. Μπορείτε να τον ξαναενεργοποιήσετε συνδεόμενοι.",
        "Pause Account": "Παύση λογαριασμού",
        "Your profile and listings will be hidden until you log in again.": "Το προφίλ και οι αγγελίες σας θα αποκρυφθούν μέχρι να συνδεθείτε ξανά.",
        "Your account has been paused. You will be signed out.": "Ο λογαριασμός σας έχει παυθεί. Θα αποσυνδεθείτε.",
        "Enter your UK bank details. Your information is stored securely and used only for payouts.": "Εισάγετε τα στοιχεία της βρετανικής τράπεζάς σας. Τα στοιχεία σας αποθηκεύονται ασφαλώς και χρησιμοποιούνται μόνο για πληρωμές.",
        "Sort code": "Κωδικός ταξινόμησης",
        "Account number": "Αριθμός λογαριασμού",
        "Account holder name": "Όνομα δικαιούχου",
        "Account label (optional)": "Ετικέτα λογαριασμού (προαιρετικό)",
        "Add Bank Account": "Προσθήκη τραπεζικού λογαριασμού",
        "Address": "Διεύθυνση",
        "Address line 1": "Διεύθυνση γραμμή 1",
        "Address line 2": "Διεύθυνση γραμμή 2",
        "Address line 2 (optional)": "Διεύθυνση γραμμή 2 (προαιρετικό)",
        "City": "Πόλη",
        "State / County": "Νομός / Κομητεία",
        "Country": "Χώρα",
        "Postcode": "Ταχυδρομικός κώδικας",
        "Your shipping address has been updated.": "Η διεύθυνση αποστολής σας ενημερώθηκε.",
        "Your account settings have been updated.": "Οι ρυθμίσεις λογαριασμού σας ενημερώθηκαν.",
        "Date of birth": "Ημερομηνία γέννησης",
        "Gender": "Φύλο",
        "Enter your card details securely. Your payment information is encrypted.": "Εισάγετε τα στοιχεία της κάρτας σας ασφαλώς. Οι πληροφορίες πληρωμής κρυπτογραφούνται.",
        "Card number": "Αριθμός κάρτας",
        "Expiry": "Λήξη",
        "CVV": "CVV",
        "Name on card": "Όνομα στην κάρτα",
        "Add Payment Card": "Προσθήκη κάρτας πληρωμής",
        "Your payment method has been saved.": "Η μέθοδος πληρωμής σας αποθηκεύτηκε.",
        "Deleting your account is permanent. You will lose access to your listings, messages, and data.": "Η διαγραφή του λογαριασμού είναι μόνιμη. Θα χάσετε την πρόσβαση στις αγγελίες, μηνύματα και δεδομένα σας.",
        "Delete Account": "Διαγραφή λογαριασμού",
        "This action cannot be undone. All your data will be permanently removed.": "Αυτή η ενέργεια δεν μπορεί να αναιρεθεί. Όλα τα δεδομένα σας θα αφαιρεθούν μόνιμα.",
        "Delete All Conversations": "Διαγραφή όλων των συνομιλιών",
        "Royal Mail": "Royal Mail",
        "DPD": "DPD",
        "Bio": "Βιογραφικό",
        "No blocked users": "Δεν υπάρχουν αποκλεισμένοι χρήστες",
        "Do you want to unblock %@?": "Θέλετε να ξεμπλοκάρετε τον %@;",
        "Blocklist": "Λίστα αποκλεισμού",
        "Active Payment method": "Ενεργή μέθοδος πληρωμής",
        "Active bank account": "Ενεργός τραπεζικός λογαριασμός",
        "No bank account added": "Δεν προστέθηκε τραπεζικός λογαριασμός",
        "Payouts are sent here when delivery is complete.": "Οι πληρωμές αποστέλλονται εδώ όταν η παράδοση ολοκληρωθεί.",
        "Seen": "Διαβάστηκε",
        "Delete": "Διαγραφή",
        "This card will be removed from your account.": "Αυτή η κάρτα θα αφαιρεθεί από τον λογαριασμό σας.",
        "Remove bank account?": "Αφαίρεση τραπεζικού λογαριασμού;",
        "Payouts will not be sent until you add a bank account again.": "Οι πληρωμές δεν θα αποστέλλονται μέχρι να προσθέσετε ξανά τραπεζικό λογαριασμό.",
        "General": "Γενικά",
        "Notification Settings": "Ρυθμίσεις ειδοποιήσεων",

        // Network / connection errors
        "Unable to connect. Please check your internet connection.": "Αδυναμία σύνδεσης. Ελέγξτε τη σύνδεσή σας στο διαδίκτυο.",
        "Connection timed out. Please try again.": "Λήξη χρόνου σύνδεσης. Δοκιμάστε ξανά.",

        // AI chat – empty results
        "I couldn't find anything matching that. Try different colours or categories.": "Δεν βρήκα τίποτα που να ταιριάζει. Δοκιμάστε άλλα χρώματα ή κατηγορίες.",
        "Do you mean \"%@\"?": "Εννοείτε \"%@\";",
        // AI chat – reply variations (happy event)
        "Happy to help! Here are some options you might like.": "Χαίρομαι να βοηθάω! Ορίστε μερικές επιλογές που μπορεί να σας αρέσουν.",
        "Sounds exciting! Here are some picks for you.": "Ακούγεται συναρπαστικό! Ορίστε μερικές επιλογές για εσάς.",
        "Let's find something great. Here are some options.": "Ας βρούμε κάτι ωραίο. Ορίστε μερικές επιλογές.",
        "Here are some items that could work perfectly.": "Ορίστε μερικά αντικείμενα που μπορεί να ταιριάξουν τέλεια.",
        "Hope you find something you love. Here are some options.": "Ελπίζω να βρείτε κάτι που σας αρέσει. Ορίστε μερικές επιλογές.",
        // AI chat – reply variations (sad event, neutral tone)
        "I understand. Here are some appropriate options.": "Κατανοώ. Ορίστε μερικές κατάλληλες επιλογές.",
        "I'll help you find something suitable.": "Θα σας βοηθήσω να βρείτε κάτι κατάλληλο.",
        "Here are some options that might work.": "Ορίστε μερικές επιλογές που μπορεί να ταιριάξουν.",
        "Let me show you some suitable options.": "Επιτρέψτε μου να σας δείξω μερικές κατάλληλες επιλογές.",
        // AI chat – reply variations (neutral)
        "Here are some items that might work.": "Ορίστε μερικά αντικείμενα που μπορεί να ταιριάξουν.",
        "Here are some options for you.": "Ορίστε μερικές επιλογές για εσάς.",
        "These might match what you're looking for.": "Αυτά μπορεί να ταιριάζουν με αυτό που ψάχνετε.",
        "Here are some picks based on your search.": "Ορίστε μερικές επιλογές βάσει της αναζήτησής σας.",
        // Chat reactions
        "Reactions": "Αντιδράσεις",
        "Search emojis": "Αναζήτηση emoji",
        "No matching emojis": "Δεν βρέθηκαν emoji",
    ]
}

// MARK: - User-facing error messages
extension L10n {
    /// Returns a short, user-friendly message for API/network errors (e.g. connection error).
    static func userFacingError(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                return L10n.string("Unable to connect. Please check your internet connection.")
            case .timedOut:
                return L10n.string("Connection timed out. Please try again.")
            case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
                return L10n.string("Unable to connect. Please check your internet connection.")
            default:
                break
            }
        }
        return error.localizedDescription
    }
}
