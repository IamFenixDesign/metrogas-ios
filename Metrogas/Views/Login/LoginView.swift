import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var store: AccountDataStore

    @State private var customerNumber = ""
    @State private var appear = false
    @State private var showOtherAccountForm = false
    @FocusState private var focusedField: Bool

    private var showContinueCard: Bool {
        session.canContinueWithCustomerNumber && !showOtherAccountForm
    }

    private var digitsOnly: String {
        customerNumber.filter(\.isNumber)
    }

    private var canSubmit: Bool {
        MetrogasURLs.normalizedCustomerNumber(customerNumber) != nil && !session.isLoggingIn
    }

    var body: some View {
        ZStack {
            LiquidGlassBackground()

            ScrollView {
                VStack(spacing: 0) {
                    brandHeader
                        .padding(.top, 56)
                        .padding(.bottom, 28)
                        .appearMotion(visible: appear, index: 0)

                    Group {
                        if showContinueCard {
                            continueCard
                        } else {
                            loginCard
                        }
                    }
                    .padding(.horizontal, 20)
                    .appearMotion(visible: appear, index: 1)

                    footerLinks
                        .padding(.top, 22)
                        .padding(.bottom, 36)
                        .appearMotion(visible: appear, index: 2)
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .onAppear {
            if customerNumber.isEmpty, let saved = session.rememberedCustomerNumber {
                customerNumber = saved
            }
            showOtherAccountForm = false
            withAnimation(MetrogasTheme.springSoft) { appear = true }
        }
    }

    private var brandHeader: some View {
        VStack(spacing: 16) {
            Image("MetrogasLogo")
                .resizable()
                .scaledToFit()
                .frame(height: 48)
                .padding(.horizontal, 28)
                .padding(.vertical, 18)
                .liquidGlass(cornerRadius: 26, prominent: true)

            Text("Oficina Virtual")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text(showContinueCard
                 ? "Tu N° de cliente quedó listo para continuar."
                 : "Ingresá con tu N° de cliente MetroGAS.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
    }

    private var continueCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(MetrogasTheme.brandBlue.opacity(0.12))
                        .frame(width: 52, height: 52)
                    Image(systemName: "number.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(MetrogasTheme.brandBlue)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Continuar")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(session.rememberedCustomerNumber ?? "")
                        .font(.headline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 0)
            }
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.55))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.5), lineWidth: 1)
                    )
            }

            if let error = session.loginError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(MetrogasTheme.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                focusedField = false
                Task { await submitLogin(session.rememberedCustomerNumber ?? customerNumber) }
            } label: {
                HStack {
                    if session.isLoggingIn {
                        ProgressView().tint(.white)
                    }
                    Text("Continuar")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(.white)
                .background {
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [MetrogasTheme.brandBlue, MetrogasTheme.brandCyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: MetrogasTheme.brandBlue.opacity(0.3), radius: 12, y: 6)
                }
            }
            .buttonStyle(PressableGlassStyle())
            .disabled(session.isLoggingIn)

            Button {
                withAnimation(MetrogasTheme.springSnappy) {
                    session.useAnotherAccount()
                    showOtherAccountForm = true
                    customerNumber = ""
                }
            } label: {
                Text("Usar otro N° de cliente")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MetrogasTheme.brandBlue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .disabled(session.isLoggingIn)
        }
        .padding(22)
        .liquidGlass(cornerRadius: 28, prominent: true)
    }

    private var loginCard: some View {
        VStack(spacing: 16) {
            Text("Es el N° de 11 dígitos que figura en tu factura MetroGAS.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            TextField("N° de cliente", text: $customerNumber)
                .keyboardType(.numberPad)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.body.monospacedDigit())
                .focused($focusedField)
                .padding(14)
                .background(fieldBackground)
                .onChange(of: customerNumber) { _, newValue in
                    let digits = newValue.filter(\.isNumber)
                    if digits != newValue {
                        customerNumber = String(digits.prefix(11))
                    } else if digits.count > 11 {
                        customerNumber = String(digits.prefix(11))
                    }
                }

            if digitsOnly.count > 0 && digitsOnly.count != 11 {
                Text("Faltan \(11 - digitsOnly.count) dígito\(11 - digitsOnly.count == 1 ? "" : "s").")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let error = session.loginError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(MetrogasTheme.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                focusedField = false
                Task { await submitLogin(customerNumber) }
            } label: {
                HStack {
                    if session.isLoggingIn {
                        ProgressView().tint(.white)
                    }
                    Text(session.isLoggingIn ? "Sincronizando…" : "Ingresar")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(.white)
                .background {
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [MetrogasTheme.brandFlame, MetrogasTheme.brandFlame.opacity(0.85)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: MetrogasTheme.brandFlame.opacity(0.35), radius: 12, y: 6)
                }
            }
            .buttonStyle(PressableGlassStyle())
            .disabled(!canSubmit)
            .opacity(canSubmit || session.isLoggingIn ? 1 : 0.55)
        }
        .padding(22)
        .liquidGlass(cornerRadius: 28, prominent: true)
    }

    private var footerLinks: some View {
        VStack(spacing: 12) {
            Link("¿Dónde veo mi N° de cliente?", destination: MetrogasURLs.saldos)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MetrogasTheme.brandBlue)

            Link("Sitio oficial MetroGAS", destination: MetrogasURLs.sitioInstitucional)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.white.opacity(0.72))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.55), lineWidth: 1)
            )
    }

    private func submitLogin(_ raw: String) async {
        await session.loginWithCustomerNumber(raw)
        if session.isAuthenticated,
           let id = session.customerNumber,
           let snapshot = session.consumePendingLoginSnapshot() {
            store.applyCustomerLoginSnapshot(snapshot, customerNumber: id)
        }
    }
}
