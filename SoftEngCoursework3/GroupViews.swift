import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct GroupDetailView: View {
    let group: GroupModel
    @State private var selectedTab: GroupTab = .chores
    
    var body: some View {
        TabView(selection: $selectedTab) {
            ChoresTabView(group: group)
                .tabItem { Label("Chores", systemImage: "checklist") }
                .tag(GroupTab.chores)
            PaymentsTabView(group: group)
                .tabItem { Label("Payments", systemImage: "creditcard") }
                .tag(GroupTab.payments)
        }
        .navigationTitle("Group Details")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if selectedTab == .chores {
                    NavigationLink(destination: CreateChoreView(group: group)) {
                        Image(systemName: "plus").font(.title2)
                    }
                } else if selectedTab == .payments {
                    NavigationLink(destination: CreatePaymentView(group: group)) {
                        Image(systemName: "plus").font(.title2)
                    }
                }
            }
        }
    }
}

struct ChoresTabView: View {
    let group: GroupModel
    @State private var chores: [Chore] = []
    @State private var message: String = ""
    @State private var selectedFilter: ChoreFilter = .all
    
    var filteredChores: [Chore] {
        switch selectedFilter {
        case .all:
            return chores
        case .week:
            if let weekInterval = Calendar.current.dateInterval(of: .weekOfYear, for: Date()) {
                return chores.filter { chore in
                    if let due = chore.dueDate {
                        return weekInterval.contains(due)
                    }
                    return false
                }
            }
            return []
        case .completed:
            return chores.filter { $0.completed }
        case .pastDeadline:
            return chores.filter { chore in
                if let due = chore.dueDate {
                    return due < Date() && !chore.completed
                }
                return false
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Group Code: \(group.code)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        if !group.memberNames.isEmpty {
                            Text("Members: " + group.memberNames.joined(separator: ", "))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                    
                    Picker("Filter", selection: $selectedFilter) {
                        ForEach(ChoreFilter.allCases) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding(.horizontal)
                    
                    Text("Chores")
                        .font(.title2)
                        .bold()
                        .padding(.top, 10)
                    
                    if !message.isEmpty { Text(message).foregroundColor(.red) }
                    
                    ForEach(filteredChores) { chore in
                        HStack {
                            NavigationLink(destination: ChoreDetailView(chore: chore, group: group)) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(chore.title).font(.headline)
                                    if let due = chore.dueDate {
                                        Text("Due: \(due.formatted(date: .abbreviated, time: .omitted))")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Text("Set by: \(chore.setBy)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Text("Assigned to: \(assignedName(for: chore.assignedTo))")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            Button { toggleChoreCompletion(chore: chore) } label: {
                                Image(systemName: chore.completed ? "checkmark.circle.fill" : "checkmark.circle")
                                    .foregroundColor(chore.completed ? .green : .gray)
                                    .font(.title2)
                            }
                        }
                        .padding()
                        .background(Color(.systemGray5))
                        .cornerRadius(8)
                    }
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Chores")
            .onAppear { fetchChores() }
        }
    }
    
    private func assignedName(for uid: String) -> String {
        if let index = group.memberIDs.firstIndex(of: uid),
           group.memberNames.indices.contains(index) {
            return group.memberNames[index]
        }
        return uid
    }
    
    private func fetchChores() {
        let db = Firestore.firestore()
        db.collection("groups").document(group.id).collection("chores")
            .order(by: "createdAt")
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    self.message = "Error fetching chores: \(error.localizedDescription)"
                    return
                }
                guard let docs = snapshot?.documents else { return }
                self.chores = docs.map { doc in
                    let data = doc.data()
                    let title = data["title"] as? String ?? ""
                    let description = data["description"] as? String ?? ""
                    let dueDate = (data["dueDate"] as? Timestamp)?.dateValue()
                    let repeatOption = data["repeat"] as? String ?? "Never"
                    let assignedTo = data["assignedTo"] as? String ?? ""
                    let setBy = data["setBy"] as? String ?? ""
                    let createdAt = (data["createdAt"] as? Timestamp)?.dateValue()
                    let completed = data["completed"] as? Bool ?? false
                    return Chore(id: doc.documentID,
                                 title: title,
                                 description: description,
                                 dueDate: dueDate,
                                 repeatOption: repeatOption,
                                 assignedTo: assignedTo,
                                 setBy: setBy,
                                 createdAt: createdAt,
                                 completed: completed)
                }
            }
    }
    
    private func toggleChoreCompletion(chore: Chore) {
        let db = Firestore.firestore()
        let newStatus = !chore.completed
        db.collection("groups").document(group.id).collection("chores").document(chore.id).updateData([
            "completed": newStatus
        ]) { error in
            if let error = error {
                self.message = "Error updating chore: \(error.localizedDescription)"
            } else {
                fetchChores()
            }
        }
    }
}

struct PaymentsTabView: View {
    let group: GroupModel
    @State private var payments: [Payment] = []
    @State private var message: String = ""
    @State private var selectedMemberIndex: Int = 0
    @State private var memberBalances: [String: Double] = [:] // What others owe you
    @State private var memberOwedBalances: [String: Double] = [:] // What you owe others
    
    // Filter out the current user from the member list
    private var filteredMembers: [(id: String, name: String)] {
        guard let currentUserID = Auth.auth().currentUser?.uid else { return [] }
        var filtered: [(id: String, name: String)] = []
        
        print("Current User ID: \(currentUserID)")
        print("Group Member IDs: \(group.memberIDs)")
        print("Group Member Names: \(group.memberNames)")
        
        for (index, memberID) in group.memberIDs.enumerated() {
            if memberID != currentUserID {
                if group.memberNames.indices.contains(index) {
                    filtered.append((id: memberID, name: group.memberNames[index]))
                } else {
                    print("Index \(index) out of bounds for memberNames: \(group.memberNames)")
                }
            } else {
                print("Excluding current user: \(memberID) at index \(index)")
            }
        }
        
        print("Filtered Members: \(filtered)")
        return filtered
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Group Code: \(group.code)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        if !group.memberNames.isEmpty {
                            Text("Members: " + group.memberNames.joined(separator: ", "))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                    
                    if !filteredMembers.isEmpty {
                        Picker("Select Person", selection: $selectedMemberIndex) {
                            ForEach(filteredMembers.indices, id: \.self) { index in
                                Text(filteredMembers[index].name).tag(index)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .padding(.horizontal)
                    }
                    
                    if !filteredMembers.isEmpty && filteredMembers.indices.contains(selectedMemberIndex) {
                        let selectedUserID = filteredMembers[selectedMemberIndex].id
                        let owesYou = memberBalances[selectedUserID] ?? 0.0
                        let youOwe = memberOwedBalances[selectedUserID] ?? 0.0
                        let net = owesYou - youOwe
                        
                        VStack(spacing: 10) {
                            Text("\(filteredMembers[selectedMemberIndex].name) owes you:")
                                .font(.headline)
                            Text("£\(String(format: "%.2f", owesYou))")
                                .font(.title)
                            
                            Text("You owe \(filteredMembers[selectedMemberIndex].name):")
                                .font(.headline)
                            Text("£\(String(format: "%.2f", youOwe))")
                                .font(.title)
                            
                            Text("Net:")
                                .font(.headline)
                            if net > 0 {
                                Text("\(filteredMembers[selectedMemberIndex].name) owes you £\(String(format: "%.2f", net))")
                                    .font(.largeTitle)
                                    .bold()
                            } else if net < 0 {
                                Text("You owe \(filteredMembers[selectedMemberIndex].name) £\(String(format: "%.2f", abs(net)))")
                                    .font(.largeTitle)
                                    .bold()
                            } else {
                                Text("Settled")
                                    .font(.largeTitle)
                                    .bold()
                            }
                            
                            NavigationLink("View Details", destination: PaymentDetailsForPersonView(payments: payments, group: group, otherMemberName: filteredMembers[selectedMemberIndex].name, otherMemberID: selectedUserID))
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                        .padding()
                    } else {
                        Text("No other members to display payments for.")
                            .padding()
                    }
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Payments")
            .onAppear { fetchPayments() }
        }
    }
    
    func updateMemberBalances() {
        var owedToYou: [String: Double] = [:] // What others owe you
        var youOwe: [String: Double] = [:] // What you owe others
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        // Initialize balances for all other members to 0
        for member in filteredMembers {
            owedToYou[member.id] = 0.0
            youOwe[member.id] = 0.0
        }
        
        for payment in payments {
            // If I set the payment, others owe me
            if payment.setByUid == currentUserId {
                for (uid, share) in payment.shares where uid != currentUserId {
                    if !share.paid {
                        owedToYou[uid, default: 0.0] += share.amount
                    }
                }
            }
            // If someone else set the payment, I might owe them
            if payment.setByUid != currentUserId, payment.shares.keys.contains(currentUserId) {
                if let myShare = payment.shares[currentUserId], !myShare.paid {
                    let creator = payment.setByUid
                    youOwe[creator, default: 0.0] += myShare.amount
                }
            }
        }
        
        self.memberBalances = owedToYou
        self.memberOwedBalances = youOwe
    }
    
    private func fetchPayments() {
        let db = Firestore.firestore()
        db.collection("groups").document(group.id).collection("payments")
            .order(by: "createdAt")
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    self.message = "Error fetching payments: \(error.localizedDescription)"
                    return
                }
                guard let docs = snapshot?.documents else {
                    self.message = "No payments found."
                    return
                }
                self.payments = docs.map { doc in
                    let data = doc.data()
                    let itemName = data["itemName"] as? String ?? ""
                    let description = data["description"] as? String ?? ""
                    let totalAmount = data["amount"] as? Double ?? 0.0
                    let setByUid = data["setByUid"] as? String ?? ""
                    let setByName = data["setByName"] as? String ?? ""
                    let createdAt = (data["createdAt"] as? Timestamp)?.dateValue()
                    
                    var shares: [String: PaymentShare] = [:]
                    if let sharesData = data["shares"] as? [String: Any] {
                        for (uid, shareData) in sharesData {
                            if let shareMap = shareData as? [String: Any],
                               let amount = shareMap["amount"] as? Double,
                               let paid = shareMap["paid"] as? Bool {
                                shares[uid] = PaymentShare(amount: amount, paid: paid)
                            }
                        }
                    }
                    
                    return Payment(id: doc.documentID,
                                   itemName: itemName,
                                   description: description,
                                   totalAmount: totalAmount,
                                   setByUid: setByUid,
                                   setByName: setByName,
                                   createdAt: createdAt,
                                   shares: shares)
                }
                updateMemberBalances()
            }
    }
}
