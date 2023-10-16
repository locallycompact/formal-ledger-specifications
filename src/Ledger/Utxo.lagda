\section{UTxO}
\label{sec:utxo}

\subsection{Accounting}

\begin{code}[hide]
{-# OPTIONS --safe #-}

open import Algebra              using (CommutativeMonoid)
open import Data.Integer.Ext     using (posPart; negPart)
open import Data.Nat.Properties  using (+-0-monoid; +-0-commutativeMonoid)
import Data.Maybe as M
import Data.Sum.Relation.Unary.All as Sum

open import Tactic.Derive.DecEq

open import Ledger.Prelude
open import Ledger.Abstract
open import Ledger.Transaction

module Ledger.Utxo
  (txs : _) (open TransactionStructure txs)
  (abs : AbstractFunctions txs) (open AbstractFunctions abs)
  where

instance
  _ = TokenAlgebra.Value-CommutativeMonoid tokenAlgebra
  _ = +-0-monoid
  _ = +-0-commutativeMonoid
  _ = ExUnit-CommutativeMonoid

  HasCoin-Map : ∀ {A} → ⦃ DecEq A ⦄ → HasCoin (A ⇀ Coin)
  HasCoin-Map .getCoin s = Σᵐᵛ[ x ← s ᶠᵐ ] x

isPhaseTwoScriptAddress : Tx → Addr → Bool
isPhaseTwoScriptAddress tx a
  with isScriptAddr? a
... | no  _ = false
... | yes p
  with lookupScriptHash (getScriptHash a p) tx
... | nothing = false
... | just s  = isP2Script s

totExUnits : Tx → ExUnits
totExUnits tx = Σᵐ[ x ← tx .wits .txrdmrs ᶠᵐ ] (x .proj₂ .proj₂)
  where open Tx; open TxWitnesses

-- utxoEntrySizeWithoutVal = 27 words (8 bytes)
utxoEntrySizeWithoutVal : MemoryEstimate
utxoEntrySizeWithoutVal = 8

utxoEntrySize : TxOut → MemoryEstimate
utxoEntrySize utxo = utxoEntrySizeWithoutVal + size (getValue utxo)

open PParams
\end{code}

Figure~\ref{fig:functions:utxo} defines functions needed for the UTxO transition system.
Figure~\ref{fig:ts-types:utxo-shelley} defines the types needed for the UTxO transition system.
The UTxO transition system is given in Figure~\ref{fig:rules:utxo-shelley}.

\begin{itemize}

  \item
    The function $\fun{outs}$ creates the unspent outputs generated by a transaction.
    It maps the transaction id and output index to the output.

  \item
    The $\fun{balance}$ function calculates sum total of all the coin in a given UTxO.
\end{itemize}

\AgdaTarget{outs, minfee, inInterval, balance}
\begin{figure*}[h]
\begin{code}[hide]
module _ (let open Tx; open TxBody) where
\end{code}
\begin{code}
  outs : TxBody → UTxO
  outs tx = mapKeys (tx .txid ,_) (tx .txouts)

  balance : UTxO → Value
  balance utxo = Σᵐᵛ[ x ← utxo ᶠᵐ ] getValue x

  cbalance : UTxO → Coin
  cbalance utxo = coin (balance utxo)

  coinPolicies : ℙ ScriptHash
  coinPolicies = policies (inject 1)

  isAdaOnlyᵇ : Value → Bool
  isAdaOnlyᵇ v = ⌊ (policies v) ≡ᵉ? coinPolicies ⌋

  minfee : PParams → Tx → Coin
  minfee pp tx  = pp .a * tx .body .txsize + pp .b
                + txscriptfee (pp .prices) (totExUnits tx)

  data DepositPurpose : Set where
    CredentialDeposit  : Credential   → DepositPurpose
    PoolDeposit        : Credential   → DepositPurpose
    DRepDeposit        : Credential   → DepositPurpose
    GovActionDeposit   : GovActionID  → DepositPurpose

  certDeposit : PParams → DCert → Maybe (DepositPurpose × Coin)
  certDeposit _   (delegate c _ _ v)  = just (CredentialDeposit c , v)
  certDeposit pp  (regpool c _)       = just (PoolDeposit       c , pp .poolDeposit)
  certDeposit _   (regdrep c v _)     = just (DRepDeposit       c , v)
  certDeposit _   _                   = nothing

  certDepositᵐ : PParams → DCert → DepositPurpose ⇀ Coin
  certDepositᵐ pp cert = case certDeposit pp cert of λ where
    (just (p , v))  → ❴ p , v ❵ᵐ
    nothing         → ∅ᵐ

  propDepositᵐ : PParams → GovActionID → GovProposal → DepositPurpose ⇀ Coin
  propDepositᵐ pp gaid record { returnAddr = record { stake = c } }
    = ❴ GovActionDeposit gaid , pp .govActionDeposit ❵ᵐ

  certRefund : DCert → Maybe DepositPurpose
  certRefund (delegate c nothing nothing x)  = just (CredentialDeposit c)
  certRefund (deregdrep c)                   = just (DRepDeposit       c)
  certRefund _                               = nothing

  certRefundˢ : DCert → ℙ DepositPurpose
  certRefundˢ = partialToSet certRefund

-- this has to be a type definition for inference to work
data inInterval (slot : Slot) : (Maybe Slot × Maybe Slot) → Set where
  both   : ∀ {l r}  → l ≤ slot × slot ≤ r  →  inInterval slot (just l   , just r)
  lower  : ∀ {l}    → l ≤ slot             →  inInterval slot (just l   , nothing)
  upper  : ∀ {r}    → slot ≤ r             →  inInterval slot (nothing  , just r)
  none   :                                    inInterval slot (nothing  , nothing)

-----------------------------------------------------
-- Boolean Functions
open HasDecPartialOrder ⦃...⦄ -- remove after #237 is merged

-- Boolean Implication
_=>ᵇ_ : Bool → Bool → Bool
a =>ᵇ b = if a then b else true

_≤ᵇ_ _≥ᵇ_ : ℕ → ℕ → Bool
m ≤ᵇ n = ⌊ m ≤? n ⌋
_≥ᵇ_ = flip _≤ᵇ_

≟-∅ᵇ : {A : Set} ⦃ _ : DecEq A ⦄ → (X : ℙ A) → Bool
≟-∅ᵇ X = ¿ X ≡ ∅ ¿ᵇ

-----------------------------------------------------

feesOK : PParams → Tx → UTxO → Bool
feesOK pp tx utxo = minfee pp tx ≤ᵇ txfee
                  ∧ not (≟-∅ᵇ (txrdmrs ˢ))
                  =>ᵇ ( allᵇ (isVKeyAddr? ∘ proj₁) collateralRange
                      ∧ isAdaOnlyᵇ bal
                      ∧ (coin bal * 100) ≥ᵇ (txfee * pp .collateralPercent)
                      ∧ not (≟-∅ᵇ collateral)
                      )
  where
    open Tx tx; open TxBody body; open TxWitnesses wits; open PParams pp
    collateralRange = range $ (utxo ∣ collateral) .proj₁
    bal             = balance (utxo ∣ collateral)
\end{code}
\begin{code}[hide]
instance
  unquoteDecl DecEq-DepositPurpose = derive-DecEq
    ((quote DepositPurpose , DecEq-DepositPurpose) ∷ [])

  HasCoin-UTxO : HasCoin UTxO
  HasCoin-UTxO .getCoin = cbalance
\end{code}

\caption{Functions used in UTxO rules}
\label{fig:functions:utxo}
\end{figure*}

\AgdaTarget{UTxOEnv, UTxOState, \_⊢\_⇀⦇\_,UTXO⦈\_}
\begin{figure*}[h]
\emph{Derived types}
\begin{code}
Deposits = DepositPurpose ⇀ Coin
\end{code}
\emph{UTxO environment}
\begin{code}
record UTxOEnv : Set where
  field slot     : Slot
        ppolicy  : Maybe ScriptHash
        pparams  : PParams
\end{code}
\emph{UTxO states}
\begin{code}
record UTxOState : Set where
  constructor ⟦_,_,_,_⟧ᵘ
  field utxo       : UTxO
        fees       : Coin
        deposits   : Deposits
        donations  : Coin
\end{code}
\emph{UTxO transitions}

\begin{code}[hide]
⟦_⟧ : {A : Set} → A → A
⟦_⟧ = id

instance
  netId? : ∀ {A : Set} {networkId : Network} {f : A → Network}
    → Dec₁ (λ a → f a ≡ networkId)
  netId? {_} {networkId} {f} .Dec₁.P? a = f a ≟ networkId

  Dec-inInterval : {slot : Slot} {I : Maybe Slot × Maybe Slot} → Dec (inInterval slot I)
  Dec-inInterval {slot} {just x  , just y } with x ≤? slot | slot ≤? y
  ... | no ¬p₁ | _      = no λ where (both (h₁ , h₂)) → ¬p₁ h₁
  ... | yes p₁ | no ¬p₂ = no λ where (both (h₁ , h₂)) → ¬p₂ h₂
  ... | yes p₁ | yes p₂ = yes (both (p₁ , p₂))
  Dec-inInterval {slot} {just x  , nothing} with x ≤? slot
  ... | no ¬p = no  (λ where (lower h) → ¬p h)
  ... | yes p = yes (lower p)
  Dec-inInterval {slot} {nothing , just x } with slot ≤? x
  ... | no ¬p = no  (λ where (upper h) → ¬p h)
  ... | yes p = yes (upper p)
  Dec-inInterval {slot} {nothing , nothing} = yes none

  HasCoin-UTxOState : HasCoin UTxOState
  HasCoin-UTxOState .getCoin s = getCoin (UTxOState.utxo s)
                               + (UTxOState.fees s)
                               + getCoin (UTxOState.deposits s)
                               + UTxOState.donations s
data
\end{code}
\begin{code}
  _⊢_⇀⦇_,UTXO⦈_ : UTxOEnv → UTxOState → Tx → UTxOState → Set
\end{code}
\caption{UTxO transition-system types}
\label{fig:ts-types:utxo-shelley}
\end{figure*}

\begin{figure*}
\begin{code}[hide]
module _ (let open UTxOState; open TxBody) where
\end{code}
\begin{code}
  updateCertDeposits : PParams → List DCert → DepositPurpose ⇀ Coin
    → DepositPurpose ⇀ Coin
  updateCertDeposits pp [] deposits = deposits
  updateCertDeposits pp (cert ∷ certs) deposits
    =  updateCertDeposits pp certs deposits ∪⁺ certDepositᵐ pp cert
    ∣  certRefundˢ cert ᶜ

  updateProposalDeposits : PParams → TxId → List GovProposal → DepositPurpose ⇀ Coin
    → DepositPurpose ⇀ Coin
  updateProposalDeposits pp txid [] deposits = deposits
  updateProposalDeposits pp txid (prop ∷ props) deposits
    =   updateProposalDeposits pp txid props deposits
    ∪⁺  propDepositᵐ pp (txid , length props) prop

  updateDeposits : PParams → TxBody → DepositPurpose ⇀ Coin → DepositPurpose ⇀ Coin
  updateDeposits pp txb
    =  updateCertDeposits pp (txb .txcerts)
    ∘  updateProposalDeposits pp (txb .txid) (txb .txprop)

  depositsChange : PParams → TxBody → DepositPurpose ⇀ Coin → ℤ
  depositsChange pp txb deposits
    =  getCoin (updateDeposits pp txb deposits)
    ⊖  getCoin deposits

  depositRefunds : PParams → UTxOState → TxBody → Coin
  depositRefunds pp st txb = negPart (depositsChange pp txb (st .deposits))

  newDeposits : PParams → UTxOState → TxBody → Coin
  newDeposits pp st txb = posPart (depositsChange pp txb (st .deposits))

  consumed : PParams → UTxOState → TxBody → Value
  consumed pp st txb
    =  balance (st .utxo ∣ txb .txins)
    +  txb .mint
    +  inject (depositRefunds pp st txb)

  produced : PParams → UTxOState → TxBody → Value
  produced pp st txb
    =  balance (outs txb)
    +  inject (txb .txfee)
    +  inject (newDeposits pp st txb)
    +  inject (txb .txdonation)
\end{code}
\caption{Functions used in UTxO rules, continued}
\label{fig:functions:utxo-2}
\end{figure*}

\begin{figure*}[h]
\begin{code}[hide]
open PParams

private variable
  Γ : UTxOEnv
  s : UTxOState
  tx : Tx

data _⊢_⇀⦇_,UTXO⦈_ where
\end{code}
\begin{code}
  UTXO-inductive :
    let open Tx tx renaming (body to txb); open TxBody txb
        open UTxOEnv Γ renaming (pparams to pp)
        open UTxOState s
    in
       txins ≢ ∅                             → txins ⊆ dom utxo
    →  inInterval slot txvldt                → minfee pp tx ≤ txfee
    →  consumed pp s txb ≡ produced pp s txb → coin mint ≡ 0
    →  txsize ≤ maxTxSize pp

    → All (λ txout →  inject (utxoEntrySize (txout .proj₂) * minUTxOValue pp)
                   ≤ᵗ getValue (txout .proj₂))
          (txouts .proj₁)
    → All (λ txout → serSize (getValue $ txout .proj₂) ≤ maxValSize pp)
          (txouts .proj₁)
    → All (Sum.All (const ⊤) (λ a → a .BootstrapAddr.attrsSize ≤ 64) ∘ proj₁)
          (range (txouts ˢ))
    → All (λ a → netId (a .proj₁) ≡ networkId) (range (txouts ˢ))
    → All (λ a → a .RwdAddr.net   ≡ networkId) (dom  (txwdrls ˢ))
    -- Add deposits

       ────────────────────────────────
       Γ ⊢ s ⇀⦇ tx ,UTXO⦈  ⟦ (utxo ∣ txins ᶜ) ∪ᵐˡ (outs txb)
                           , fees + txfee
                           , updateDeposits pp txb deposits
                           , donations + txdonation
                           ⟧ᵘ

\end{code}
\begin{code}[hide]
instance
  Computational-UTXO : Computational _⊢_⇀⦇_,UTXO⦈_
  Computational-UTXO = record {go} where module go Γ s tx where
    open Tx tx renaming (body to txb); open TxBody txb
    open UTxOEnv Γ renaming (pparams to pp)
    open UTxOState s

    UTXO-premises : Set
    UTXO-premises
      = txins ≢ ∅
      × txins ⊆ dom utxo
      × inInterval slot txvldt
      × minfee pp tx ≤ txfee
      × consumed pp s txb ≡ produced pp s txb
      × coin mint ≡ 0
      × txsize ≤ maxTxSize pp
      × All (λ txout →  inject (utxoEntrySize (txout .proj₂) * minUTxOValue pp)
                    ≤ᵗ getValue (txout .proj₂))
            (txouts .proj₁)
      × All (λ txout → serSize (getValue $ txout .proj₂) ≤ maxValSize pp)
            (txouts .proj₁)
      × All (Sum.All (const ⊤) (λ a → a .BootstrapAddr.attrsSize ≤ 64) ∘ proj₁)
            (range (txouts ˢ))
      × All (λ a → netId (a .proj₁) ≡ networkId) (range (txouts ˢ))
      × All (λ a → a .RwdAddr.net   ≡ networkId) (dom  (txwdrls ˢ))

    UTXO-premises? : Dec UTXO-premises
    UTXO-premises? = ¿ UTXO-premises ¿

    computeProof =
      case UTXO-premises? of λ where
        (yes (p₀ , p₁ , p₂ , p₃ , p₄ , p₅ , p₆ , p₇ , p₈ , p₉ , p₁₀ , p₁₁)) →
          just (_ , UTXO-inductive p₀ p₁ p₂ p₃ p₄ p₅ p₆ p₇ p₈ p₉ p₁₀ p₁₁)
        (no _) → nothing

    completeness : ∀ s' → Γ ⊢ s ⇀⦇ tx ,UTXO⦈ s' → _
    completeness s' h@(UTXO-inductive q₀ q₁ q₂ q₃ q₄ q₅ q₆ q₇ q₈ q₉ q₁₀ q₁₁) = QED
      where
      QED : map proj₁ computeProof ≡ just s'
      QED with UTXO-premises?
      ... | yes _ = refl
      ... | no q = ⊥-elim
                 $ q (q₀ , q₁ , q₂ , q₃ , q₄ , q₅ , q₆ , q₇ , q₈ , q₉ , q₁₀ , q₁₁)
\end{code}
\caption{UTXO inference rules}
\label{fig:rules:utxo-shelley}
\end{figure*}
