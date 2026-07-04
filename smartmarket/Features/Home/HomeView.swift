import SwiftUI

struct HomeView: View {

    @State private var vm = HomeViewModel()
    @State private var showCalorieDetail = false
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color.surfaceGrouped.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        headerBanner
                        VStack(spacing: 16) {
                            calorieCard
                            mealSectionsCard
                            agentCard
                            dealsSection
                            mealPlanPreview
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 32)
                    }
                }
                .refreshable { await vm.refresh() }

                // Deal banner drops from top
                if let deal = vm.activeDealBanner {
                    DealNotificationBanner(
                        deal: deal,
                        onBuy:  { Task { await vm.respondToDeal(deal, bought: true) } },
                        onSkip: { Task { await vm.respondToDeal(deal, bought: false) } }
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(10)
                }
            }
            .overlay(alignment: .bottomTrailing) { quickLogButton }
            .animation(reduceMotion ? .none : .spring(response: 0.45, dampingFraction: 0.8),
                       value: vm.activeDealBanner?.id)
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $vm.showLogSheet) { LogFoodSheet(vm: vm) }
        .sheet(isPresented: $vm.showAgentChat) { AgentChatSheet(vm: vm) }
        .task { await vm.load() }
        .onAppear { LocationService.shared.startUpdating() }
    }

    // MARK: - Header banner

    private var headerBanner: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [Color.brandHeader, Color.brandHeaderMid],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)

            // Decorative circle
            Circle()
                .fill(.white.opacity(0.05))
                .frame(width: 200, height: 200)
                .offset(x: 140, y: -30)
                .blur(radius: 20)

            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 14) {
                    // Avatar
                    ZStack {
                        Circle()
                            .fill(.white.opacity(0.2))
                            .frame(width: 48, height: 48)
                        Text(profileName.prefix(1).uppercased())
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    .overlay(Circle().strokeBorder(.white.opacity(0.4), lineWidth: 1.5))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(greeting)
                            .font(.caption).fontWeight(.medium)
                            .foregroundStyle(.white.opacity(0.7))
                        Text(profileName.isEmpty ? "Welcome!" : profileName)
                            .font(.title3).fontWeight(.bold)
                            .foregroundStyle(.white)
                    }

                    Spacer()

                    // Date pill
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(Date(), format: .dateTime.weekday(.abbreviated))
                            .font(.caption2).foregroundStyle(.white.opacity(0.6))
                            .textCase(.uppercase)
                        Text(Date(), format: .dateTime.day().month(.abbreviated))
                            .font(.subheadline).fontWeight(.semibold).foregroundStyle(.white)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                }
                .padding(.horizontal, 20)
                .padding(.top, 58)
                .padding(.bottom, 20)

                // Quick stats strip
                HStack(spacing: 0) {
                    quickStat(label: "Today", value: "\(Int(vm.consumed)) kcal", icon: "flame.fill", color: .brandAmber)
                    Divider().frame(height: 30).overlay(Color.white.opacity(0.2))
                    quickStat(label: "Goal", value: "\(Int(vm.goal)) kcal", icon: "target", color: .white)
                    Divider().frame(height: 30).overlay(Color.white.opacity(0.2))
                    quickStat(label: "Deals", value: "\(vm.nearbyDeals.count) near you", icon: "tag.fill", color: Color(hex: "#86EFAC"), isRefreshing: vm.isRefreshing)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 18)
            }
        }
        .frame(maxWidth: .infinity)
        // Gradient fade into the grouped background so cards appear to emerge from the header
        .overlay(alignment: .bottom) {
            LinearGradient(
                colors: [.clear, Color.surfaceGrouped],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 22)
            .allowsHitTesting(false)
        }
    }

    private func quickStat(label: String, value: String, icon: String, color: Color, isRefreshing: Bool = false) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(value)
                        .font(.caption).fontWeight(.semibold).foregroundStyle(.white)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    if isRefreshing {
                        ProgressView()
                            .scaleEffect(0.45)
                            .tint(.white.opacity(0.7))
                    }
                }
                Text(label)
                    .font(.caption2).foregroundStyle(.white.opacity(0.55))
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Calorie card

    private var calorieCard: some View {
        VStack(spacing: 0) {
            // Top: ring + calorie text side by side
            HStack(spacing: 20) {
                CalorieRingView(consumed: vm.consumed, goal: vm.goal, size: 120)
                    .frame(width: 120, height: 120)
                    .onTapGesture { showCalorieDetail.toggle() }
                    .popover(isPresented: $showCalorieDetail, attachmentAnchor: .point(.center), arrowEdge: .trailing) {
                        calorieDetailPopover
                    }
                    .accessibilityHint("Tap for calorie breakdown")

                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Calories Today")
                            .font(.caption).fontWeight(.medium)
                            .foregroundStyle(.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text("\(Int(vm.consumed))")
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                                .monospacedDigit()
                                .minimumScaleFactor(0.6)
                                .lineLimit(1)
                            Text("/ \(Int(vm.goal))")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                                .minimumScaleFactor(0.7)
                                .lineLimit(1)
                            Text("kcal")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button { vm.openLog() } label: {
                        Label("Log Food", systemImage: "plus.circle.fill")
                            .font(.caption).fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Color.brandPrimary, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
            .padding(18)

            Divider().padding(.horizontal, 18)

            // Bottom: macro row
            HStack(spacing: 0) {
                macroTile(label: "Protein", symbol: "bolt.fill",
                          current: vm.proteinCurrent, goal: vm.proteinGoal,
                          color: .proteinAccent,
                          tooltip: "Protein builds and repairs muscle. Your target is \(Int(vm.proteinGoal))g/day based on your weight and goal.")
                macroSeparator
                macroTile(label: "Carbs", symbol: "leaf.fill",
                          current: vm.carbsCurrent, goal: vm.carbsGoal,
                          color: .carbsAccent,
                          tooltip: "Carbohydrates are your body's primary fuel. Choose complex sources like oats, rice, and legumes.")
                macroSeparator
                macroTile(label: "Fat", symbol: "drop.fill",
                          current: vm.fatCurrent, goal: vm.fatGoal,
                          color: .fatAccent,
                          tooltip: "Healthy fats support hormones and brain function. Include olive oil, nuts, and fatty fish.")
            }
            .padding(.vertical, 14)
        }
        .premiumCard()
    }

    private func macroTile(label: String, symbol: String,
                           current: Double, goal: Double, color: Color, tooltip: String) -> some View {
        VStack(spacing: 5) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 28, height: 28)
                    .background(color.opacity(0.12), in: Circle())
                InfoTooltip(text: tooltip)
                    .offset(x: 10, y: -8)
            }
            .frame(width: 38, height: 36)
            Text("\(Int(current))g")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .monospacedDigit()
            Text("of \(Int(goal))g")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(label)
                .font(.caption2).fontWeight(.semibold)
                .foregroundStyle(color)
            ProgressView(value: min(max(current, 0), goal), total: max(goal, 1))
                .tint(color)
                .frame(width: 44)
                .padding(.top, 1)
        }
        .frame(maxWidth: .infinity)
    }

    private var calorieDetailPopover: some View {
        let remaining = max(vm.goal - Int(vm.consumed), 0)
        let over = max(Int(vm.consumed) - vm.goal, 0)
        let pct = vm.goal > 0 ? min(Int(Double(vm.consumed) / Double(vm.goal) * 100), 100) : 0
        return VStack(alignment: .leading, spacing: 10) {
            Text("Calorie Summary")
                .font(.headline)
            Divider()
            calorieRow("Consumed", value: "\(Int(vm.consumed)) kcal", color: .primary)
            calorieRow("Daily Goal", value: "\(vm.goal) kcal", color: .secondary)
            calorieRow(over > 0 ? "Over by" : "Remaining",
                       value: "\(over > 0 ? over : remaining) kcal",
                       color: over > 0 ? .brandDanger : .brandPrimary)
            Divider()
            Text("\(pct)% of daily goal")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
        .padding(16)
        .frame(minWidth: 210)
        .presentationCompactAdaptation(.popover)
    }

    private func calorieRow(_ label: String, value: String, color: Color) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).bold().foregroundStyle(color)
        }
    }

    private var macroSeparator: some View {
        Rectangle()
            .fill(Color(.separator).opacity(0.4))
            .frame(width: 0.5, height: 64)
    }

    // MARK: - Agent card

    private var agentCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    LinearGradient(colors: [Color.brandPrimary, Color.brandDark],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                        .clipShape(Circle())
                        .frame(width: 36, height: 36)
                    Text("SM")
                        .font(.caption).fontWeight(.bold)
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Mealio Agent")
                        .font(.subheadline).fontWeight(.semibold)
                    Text("AI-powered meal & deal assistant")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                if appState.isGeneratingMealPlan {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.7)
                            .tint(Color.brandPrimary)
                        Text("Thinking…")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }

            AgentMessageCardView(
                message: vm.mealPlan?.agentNotes,
                isLoading: vm.isLoading || appState.isGeneratingMealPlan
            )

            Button {
                vm.showAgentChat = true
            } label: {
                HStack {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                    Text("Ask Agent")
                        .fontWeight(.semibold)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption).fontWeight(.semibold)
                        .opacity(0.7)
                }
                .font(.subheadline)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(
                    LinearGradient(colors: [Color.brandPrimary, Color.brandDark],
                                   startPoint: .leading, endPoint: .trailing),
                    in: RoundedRectangle(cornerRadius: 12)
                )
            }
        }
        .padding(16)
        .premiumCard()
    }

    // MARK: - Deals section

    private var dealsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "tag.fill")
                        .foregroundStyle(Color.brandPrimary)
                    Text("Deals Near You")
                        .font(.headline)
                }
                Spacer()
                if !vm.nearbyDeals.isEmpty {
                    Text("\(vm.nearbyDeals.count) deals")
                        .font(.caption).fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.brandPrimary, in: Capsule())
                }
            }

            if vm.isLoading {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(0..<3, id: \.self) { _ in SkeletonDealCard() }
                    }
                    .padding(.horizontal, 1)
                }
            } else if vm.nearbyDeals.isEmpty {
                emptyDealsRow
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(vm.nearbyDeals) { deal in
                            DealCardView(deal: deal) { vm.activeDealBanner = deal }
                        }
                    }
                    .padding(.horizontal, 1)
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(16)
        .premiumCard()
    }

    private var emptyDealsRow: some View {
        HStack(spacing: 14) {
            Image(systemName: "location.magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(Color.brandPrimary.opacity(0.35))
            VStack(alignment: .leading, spacing: 3) {
                Text("No nearby deals found")
                    .font(.subheadline).fontWeight(.semibold)
                Text("Make sure the backend is running and pull to refresh")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 10)
    }

    // MARK: - Meal plan preview

    private var mealPlanPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Today's Meals", systemImage: "fork.knife.circle.fill")
                    .font(.headline)
                Spacer()
                NavigationLink {
                    MealPlanView()
                } label: {
                    Text("Full Plan")
                        .font(.caption).fontWeight(.semibold)
                        .foregroundStyle(Color.brandPrimary)
                }
            }

            if vm.isLoading {
                ForEach(0..<4, id: \.self) { _ in
                    Rectangle()
                        .fill(Color(.systemFill))
                        .frame(height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .shimmer(active: !reduceMotion)
                }
            } else if let plan = vm.mealPlan {
                ForEach(Array(plan.allMeals.enumerated()), id: \.offset) { idx, meal in
                    MealPreviewRow(
                        icon: meal.sfSymbol,
                        title: meal.title,
                        calories: meal.entries.reduce(0) { $0 + $1.calories },
                        accent: mealAccent(idx)
                    )
                    if idx < plan.allMeals.count - 1 {
                        Divider().padding(.leading, 36)
                    }
                }
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "wand.and.stars")
                        .foregroundStyle(Color.brandPrimary.opacity(0.5))
                    Text("Pull to refresh and generate today's plan")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }
        }
        .padding(16)
        .premiumCard()
    }

    // MARK: - Meal sections (today's log)

    private var mealSectionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Today's Log", systemImage: "list.bullet.clipboard.fill")
                    .font(.headline)
                Spacer()
                Text("\(vm.remaining) kcal left")
                    .font(.caption).fontWeight(.semibold)
                    .foregroundStyle(Color.calorieAccent)
                    .contentTransition(.numericText())
            }
            ForEach(Array(MealSlot.allCases.enumerated()), id: \.element) { idx, slot in
                MealSlotRow(
                    slot: slot,
                    entries: vm.entries(for: slot),
                    onAdd: { vm.openLog(slot: slot) },
                    onDelete: { vm.removeLog($0) }
                )
                if idx < MealSlot.allCases.count - 1 {
                    Divider().padding(.leading, 40)
                }
            }
        }
        .padding(16)
        .premiumCard()
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: vm.consumed)
    }

    private var quickLogButton: some View {
        Button { vm.openLog() } label: {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(
                    LinearGradient(colors: [Color.calorieAccent, Color.calorieAccent.opacity(0.82)],
                                   startPoint: .top, endPoint: .bottom),
                    in: Circle()
                )
                .shadow(color: Color.calorieAccent.opacity(0.45), radius: 12, x: 0, y: 5)
        }
        .padding(.trailing, 20)
        .padding(.bottom, 28)
        .accessibilityLabel("Log food")
    }

    // MARK: - Helpers

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default:      return "Good evening"
        }
    }

    private var profileName: String {
        let name = AppState.shared.userProfile.name
        return name.isEmpty ? "there" : name
    }

    private func mealAccent(_ idx: Int) -> Color {
        [Color.brandPrimary, Color.brandAmber, Color(hex: "#0EA5E9"), Color(hex: "#8B5CF6")][idx % 4]
    }
}

// MARK: - Sub-views

private struct MealPreviewRow: View {
    let icon: String
    let title: String
    let calories: Int
    let accent: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 28, height: 28)
                .background(accent.opacity(0.12))
                .clipShape(Circle())

            Text(title)
                .font(.subheadline).fontWeight(.medium)
                .lineLimit(1)
            Spacer()
            Text("\(calories) kcal")
                .font(.caption).fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 2)
    }
}

private struct SkeletonDealCard: View {
    @State private var phase: CGFloat = -1

    var body: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(Color(.systemFill))
            .frame(width: 160, height: 100)
            .shimmer(active: true)
    }
}


// MARK: - Meal slot row (one meal's logged items)

private struct MealSlotRow: View {
    let slot: MealSlot
    let entries: [FoodLogEntry]
    let onAdd: () -> Void
    let onDelete: (FoodLogEntry) -> Void

    private var kcal: Int { entries.reduce(0) { $0 + $1.calories } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: slot.sfSymbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(slot.accent)
                    .frame(width: 30, height: 30)
                    .background(slot.accent.opacity(0.12), in: Circle())

                Text(slot.title)
                    .font(.subheadline).fontWeight(.semibold)

                Spacer()

                if kcal > 0 {
                    Text("\(kcal) kcal")
                        .font(.caption).fontWeight(.semibold)
                        .foregroundStyle(.secondary).monospacedDigit()
                }

                Button(action: onAdd) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(slot.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add to \(slot.title)")
            }

            ForEach(entries) { entry in
                HStack(spacing: 8) {
                    Text(entry.name)
                        .font(.caption).foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer()
                    Text("\(entry.servingG)g")
                        .font(.caption2).foregroundStyle(.secondary)
                    Text("\(entry.calories)")
                        .font(.caption2).fontWeight(.semibold)
                        .foregroundStyle(.secondary).monospacedDigit()
                    Button { onDelete(entry) } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.brandDanger.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove logged food")
                }
                .padding(.leading, 40)
            }
        }
    }
}

#Preview { HomeView() }

// MARK: - Agent Chat Sheet (FIXED CRASH)

struct AgentChatSheet: View {
    @Bindable var vm: HomeViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var inputFocused: Bool
    
    // FIX 1: Purely local @State string strictly isolates keystrokes from background model tasks
    @State private var localInput: String = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            if vm.chatMessages.isEmpty {
                                VStack(spacing: 8) {
                                    Image(systemName: "brain.head.profile")
                                        .font(.system(size: 44))
                                        .foregroundStyle(Color.brandPrimary)
                                    Text("Ask me anything about your meals, deals, or nutrition goals.")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                                .padding(.top, 60)
                                .padding(.horizontal, 32)
                            }
                            ForEach(vm.chatMessages) { msg in
                                ChatBubble(message: msg)
                                    .id(msg.id.uuidString)
                            }
                            if vm.isChatLoading {
                                HStack {
                                    TypingIndicator()
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .id("typing")
                            }
                        }
                        .padding(.vertical, 16)
                    }
                    .onChange(of: vm.chatMessages.count) {
                        withAnimation {
                            proxy.scrollTo(vm.chatMessages.last?.id.uuidString ?? "typing", anchor: .bottom)
                        }
                    }
                    .onChange(of: vm.isChatLoading) {
                        if vm.isChatLoading {
                            withAnimation { proxy.scrollTo("typing", anchor: .bottom) }
                        }
                    }
                }

                Divider()

                HStack(spacing: 10) {
                    // FIX 2: Bind safely to local buffer state variable
                    TextField("Ask about meals, deals, nutrition…", text: $localInput)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.sentences)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
                        .focused($inputFocused)
                        .submitLabel(.send)
                        .onSubmit {
                            let cleaned = localInput.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !cleaned.isEmpty else { return }
                            
                            // Commit payload to VM main actor sequence securely on button fire/return
                            vm.chatInput = cleaned
                            localInput = ""
                            Task { await vm.sendChatMessage() }
                        }

                    Button {
                        let cleaned = localInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        vm.chatInput = cleaned
                        localInput = ""
                        Task { await vm.sendChatMessage() }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(localInput.trimmingCharacters(in: .whitespaces).isEmpty || vm.isChatLoading
                                ? Color.secondary : Color.brandPrimary)
                    }
                    .accessibilityLabel("Send message")
                    .disabled(localInput.trimmingCharacters(in: .whitespaces).isEmpty || vm.isChatLoading)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .navigationTitle("Mealio Agent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear { }
    }
}

// MARK: - Chat Bubble

private struct ChatBubble: View {
    let message: ChatMessage

    var isUser: Bool { message.role == "user" }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 60) }
            Text(message.content)
                .font(.subheadline)
                .foregroundStyle(isUser ? .white : .primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    isUser ? Color.brandPrimary : Color(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 18)
                )
            if !isUser { Spacer(minLength: 60) }
        }
        .padding(.horizontal, 16)
    }
}

// MARK: - Typing Indicator

private struct TypingIndicator: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 8, height: 8)
                    .scaleEffect(animating ? 1.3 : 0.8)
                    .opacity(animating ? 1.0 : 0.4)
                    .animation(
                        .easeInOut(duration: 0.5).repeatForever(autoreverses: true).delay(Double(i) * 0.18),
                        value: animating
                    )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
        .onAppear { animating = true }
    }
}
