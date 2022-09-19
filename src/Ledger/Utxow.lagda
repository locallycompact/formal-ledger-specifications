\subsection{Witnessing}
\begin{code}[hide]
{-# OPTIONS --safe #-}

open import Ledger.Transaction

module Ledger.Utxow (txs : TransactionStructure) where

open import Prelude

import Data.Maybe
import Data.Nat
open import Interface.ComputationalRelation
open import Interface.DecEq
open import Data.FinMap
open import Data.FinSet renaming (FinSet to ℙ_)

open TransactionStructure txs
open import Ledger.Crypto
open import Ledger.Script KeyHash ScriptHash ℕ Data.Nat._≤_ Data.Nat._≤ᵇ_
open import Ledger.Utxo txs

open TxBody
open TxWitnesses
open Tx
\end{code}

\begin{figure*}[h]
\begin{code}
witsVKeyNeeded : UTxO → TxBody → ℙ KeyHash
witsVKeyNeeded utxo txb =
  mapPartial ((λ { (inj₁ kh) → just kh ; _ → nothing }) ∘ payCred ∘ proj₁) (utxo ⟪$⟫ txins txb)

scriptsNeeded : UTxO → TxBody → ℙ ScriptHash
scriptsNeeded utxo txb =
  mapPartial ((λ { (inj₂ sh) → just sh ; _ → nothing }) ∘ payCred ∘ proj₁) (utxo ⟪$⟫ txins txb)

scriptsP1 : TxWitnesses → ℙ P1Script
scriptsP1 txw = mapPartial (λ { (inj₁ s) → just s ; _ → nothing }) (scripts txw)
\end{code}
\caption{Functions used for witnessing}
\label{fig:functions:utxow}
\end{figure*}

\begin{figure*}[h]
\begin{code}[hide]
data
\end{code}
\begin{code}
  _⊢_⇀⦇_,UTXOW⦈_ : UTxOEnv → UTxOState → Tx → UTxOState → Set
\end{code}
\caption{UTxOW transition-system types}
\label{fig:ts-types:utxow}
\end{figure*}

\begin{figure*}[h]
\begin{code}[hide]
data _⊢_⇀⦇_,UTXOW⦈_ where
\end{code}
\begin{code}
  UTXOW-inductive :
    ∀ {Γ} {s} {tx} {s'}
    → let utxo = UTxOState.utxo s
          txb = body tx
          txw = wits tx
          witsKeyHashes = Data.FinSet.map hash (dom (vkSigs txw))
          witsScriptHashes = Data.FinSet.map hash (scripts txw)
      in
    Data.FinMap.All (λ where (vk , σ) → isSigned vk (txidBytes (txid txb)) σ) (vkSigs txw)
    → Data.FinSet.All (validP1Script witsKeyHashes (txvldt txb)) (scriptsP1 txw)
    → witsVKeyNeeded utxo txb ⊆ witsKeyHashes
    → scriptsNeeded utxo txb ≡ᵉ witsScriptHashes
    -- TODO: check genesis signatures
    → txADhash txb ≡ Data.Maybe.map hash (txAD tx)
    → Γ ⊢ s ⇀⦇ txb ,UTXO⦈ s'
    ────────────────────────────────
    Γ ⊢ s ⇀⦇ tx ,UTXOW⦈ s'
\end{code}
\caption{UTXOW inference rules}
\label{fig:rules:utxow}
\end{figure*}