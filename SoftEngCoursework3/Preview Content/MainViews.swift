import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct ContentView: View {
    var body: some View {
        NavigationStack {
            LoginView()
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .signUp:
                        SignUpView()
                    }
                }
                .navigationDestination(for: GroupModel.self) { group in
                    GroupDetailView(group: group)
                }
        }
    }
}

struct LoginView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var message = ""
    @State private var isLoggedIn = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .frame(width: 100, height: 100)
                .foregroundColor(.blue)
                .padding(.top, 50)
            TextField("Email", text: $email)
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)
            SecureField("Password", text: $password)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)
            Button("Login") {
                loginUser()
            }
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue)
            .cornerRadius(8)
            if !message.isEmpty {
                Text(message)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            HStack {
                Text("Don't have an account?")
                NavigationLink("Sign Up", value: Route.signUp)
            }
            .padding(.bottom, 30)
        }
        .padding(.horizontal)
        .navigationDestination(isPresented: $isLoggedIn) {
            HomeView()
        }
    }
    
    private func loginUser() {
        Auth.auth().signIn(withEmail: email, password: password) { authResult, error in
            if let error = error {
                self.message = "Login error: \(error.localizedDescription)"
                return
            }
            self.message = "Login successful!"
            self.isLoggedIn = true
        }
    }
}

struct SignUpView: View {
    @Environment(\.dismiss) var dismiss
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var message = ""
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.crop.circle.badge.plus")
                .resizable()
                .frame(width: 100, height: 100)
                .foregroundColor(.green)
                .padding(.top, 50)
            TextField("First Name", text: $firstName)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)
            TextField("Last Name", text: $lastName)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)
            TextField("Email (e.g. user@example.com)", text: $email)
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)
            SecureField("Password (6+ chars)", text: $password)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)
            Button("Sign Up") {
                signUpUser()
            }
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.green)
            .cornerRadius(8)
            if !message.isEmpty {
                Text(message)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            Spacer()
        }
        .padding(.horizontal)
    }
    
    private func signUpUser() {
        Auth.auth().createUser(withEmail: email, password: password) { authResult, error in
            if let error = error {
                self.message = "Sign up error: \(error.localizedDescription)"
                return
            }
            guard let user = authResult?.user else { return }
            let db = Firestore.firestore()
            db.collection("users").document(user.uid).setData([
                "email": email,
                "firstName": firstName,
                "lastName": lastName,
                "createdAt": FieldValue.serverTimestamp()
            ]) { err in
                if let err = err {
                    self.message = "Firestore error: \(err.localizedDescription)"
                } else {
                    self.message = "Sign up successful! Returning to login..."
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct HomeView: View {
    @State private var userName: String = "Welcome!"
    @State private var groups: [GroupModel] = []
    @State private var joinCode: String = ""
    @State private var message: String = ""
    @State private var selectedGroup: GroupModel? = nil
    @State private var showingJoinSheet = false
    
    private let lightGreen = Color(red: 0.8, green: 1.0, blue: 0.8)
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text(userName)
                    .font(.largeTitle)
                    .padding(.top, 50)
                
                // Group Management Section
                VStack(spacing: 15) {
                    Button(action: { createGroup() }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("Create New Group")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(10)
                    }
                    
                    Button(action: { showingJoinSheet = true }) {
                        HStack {
                            Image(systemName: "person.2.fill")
                            Text("Join a Group")
                        }
                        .font(.headline)
                        .foregroundColor(.green)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(lightGreen)
                        .cornerRadius(10)
                    }
                }
                
                if !message.isEmpty {
                    Text(message)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                }
                
                // Groups List
                if !groups.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Your Groups")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        ForEach(groups, id: \.id) { group in
                            Button(action: { selectedGroup = group }) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("Group Code: \(group.code)")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    if !group.memberNames.isEmpty {
                                        Text("Members: " + group.memberNames.joined(separator: ", "))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    } else {
                                        Text("Members: Loading...")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                            }
                        }
                    }
                }
                
                Spacer()
            }
            .padding()
        }
        .navigationTitle("Home")
        .onAppear {
            fetchUserName()
            fetchGroups()
        }
        .navigationDestination(item: $selectedGroup) { group in
            GroupDetailView(group: group)
        }
        .sheet(isPresented: $showingJoinSheet) {
            JoinGroupSheet(joinCode: $joinCode, message: $message, onJoin: joinGroup)
                .presentationDetents([.medium])
        }
    }
    
    private func fetchUserName() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let db = Firestore.firestore()
        db.collection("users").document(uid).getDocument { doc, error in
            if let doc = doc, doc.exists {
                let data = doc.data()
                let firstName = data?["firstName"] as? String ?? ""
                let lastName = data?["lastName"] as? String ?? ""
                DispatchQueue.main.async {
                    self.userName = "Welcome, \(firstName) \(lastName)!"
                }
            }
        }
    }
    
    private func fetchGroups() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let db = Firestore.firestore()
        db.collection("groups")
            .whereField("members", arrayContains: uid)
            .getDocuments { snapshot, error in
                if let error = error {
                    self.message = "Error fetching groups: \(error.localizedDescription)"
                    return
                }
                guard let documents = snapshot?.documents else {
                    self.message = "No groups found."
                    return
                }
                var tempGroups: [GroupModel] = []
                for doc in documents {
                    let data = doc.data()
                    let code = data["code"] as? String ?? ""
                    let ownerId = data["ownerId"] as? String ?? ""
                    let memberIDs = data["members"] as? [String] ?? []
                    let group = GroupModel(id: doc.documentID, code: code, ownerId: ownerId, memberIDs: memberIDs)
                    tempGroups.append(group)
                }
                self.groups = tempGroups
                for i in 0..<self.groups.count {
                    self.fetchMemberNames(for: self.groups[i], index: i)
                }
            }
    }
    
    private func fetchMemberNames(for group: GroupModel, index groupIndex: Int) {
        let db = Firestore.firestore()
        var names: [String] = []
        var nameToUidMap: [String: String] = [:] // Map to maintain order
        let memberUIDs = group.memberIDs
        let dispatchGroup = DispatchGroup()
        
        print("Fetching names for group \(group.id) with member IDs: \(memberUIDs)")
        
        for uid in memberUIDs {
            dispatchGroup.enter()
            db.collection("users").document(uid).getDocument { doc, error in
                if let doc = doc, doc.exists {
                    let data = doc.data()
                    let firstName = data?["firstName"] as? String ?? ""
                    let lastName = data?["lastName"] as? String ?? ""
                    let fullName = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
                    nameToUidMap[uid] = fullName
                } else {
                    print("Failed to fetch user \(uid): \(error?.localizedDescription ?? "Unknown error")")
                    nameToUidMap[uid] = uid // Fallback to UID if name not found
                }
                dispatchGroup.leave()
            }
        }
        
        dispatchGroup.notify(queue: .main) {
            // Reconstruct names in the same order as memberIDs
            for uid in memberUIDs {
                if let name = nameToUidMap[uid] {
                    names.append(name)
                } else {
                    names.append(uid) // Fallback if somehow missing
                }
            }
            print("Fetched names for group \(group.id): \(names)")
            self.groups[groupIndex].memberNames = names
            self.groups = self.groups // Trigger UI update
        }
    }
    
    private func joinGroup() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let db = Firestore.firestore()
        db.collection("groups")
            .whereField("code", isEqualTo: joinCode)
            .getDocuments { snapshot, error in
                if let error = error {
                    self.message = "Error joining group: \(error.localizedDescription)"
                    return
                }
                guard let docs = snapshot?.documents, !docs.isEmpty else {
                    self.message = "No group found with that code."
                    return
                }
                let groupDoc = docs[0]
                let groupID = groupDoc.documentID
                let currentMembers = groupDoc.data()["members"] as? [String] ?? []
                var newMembers = currentMembers
                if !newMembers.contains(uid) {
                    newMembers.append(uid)
                }
                db.collection("groups").document(groupID).setData(["members": newMembers], merge: true) { err in
                    if let err = err {
                        self.message = "Error joining group: \(err.localizedDescription)"
                    } else {
                        self.message = "Successfully joined group!"
                        self.joinCode = ""
                        self.fetchGroups()
                        self.showingJoinSheet = false
                    }
                }
            }
    }
    
    private func createGroup() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let db = Firestore.firestore()
        let code = generateGroupCode()
        db.collection("groups").document().setData([
            "code": code,
            "ownerId": uid,
            "members": [uid]
        ]) { error in
            if let error = error {
                self.message = "Error creating group: \(error.localizedDescription)"
            } else {
                self.message = "Group created with code \(code)!"
                self.fetchGroups()
            }
        }
    }
}

struct JoinGroupSheet: View {
    @Binding var joinCode: String
    @Binding var message: String
    var onJoin: () -> Void
    @Environment(\.dismiss) var dismiss
    
    private let lightGreen = Color(red: 0.8, green: 1.0, blue: 0.8)
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Join a Group")
                .font(.title2)
                .bold()
                .foregroundColor(.green)
            
            TextField("Enter Group Code", text: $joinCode)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()
                .background(lightGreen.opacity(0.3))
                .cornerRadius(8)
                .submitLabel(.join)
                .onSubmit {
                    onJoin()
                }
            
            Button(action: onJoin) {
                Text("Join Group")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .cornerRadius(10)
            }
            
            Button(action: { dismiss() }) {
                Text("Cancel")
                    .foregroundColor(.gray)
            }
            
            if !message.isEmpty && message.contains("Error") || message.contains("No group found") {
                Text(message)
                    .foregroundColor(.red)
                    .font(.caption)
            }
        }
        .padding()
        .background(lightGreen.opacity(0.1))
    }
}
