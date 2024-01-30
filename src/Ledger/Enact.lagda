\section{Enactment}
\label{sec:enactment}
\begin{code}[hide]
{-# OPTIONS --safe #-}

open import Data.Nat.Properties using (+-0-monoid)
open import Data.Rational using (ℚ)

open import Ledger.Prelude
open import Ledger.Types.GovStructure

module Ledger.Enact (gs : _) (open GovStructure gs) where

open import Ledger.GovernanceActions gs
\end{code}

Figure~\ref{fig:enact-defs} contains some definitions required to
define the ENACT transition system. \EnactEnv is the environment and
\EnactState the state of ENACT, which enacts a governance action. All
governance actions except \TreasuryWdrl and \Info modify \EnactState, which of course can have further
consequences. Also, enacting these governance actions is the
\emph{only} way of modifying \EnactState. The \withdrawals field of
\EnactState is special in that it is ephemeral---ENACT accumulates
withdrawals there which are paid out at the next epoch boundary where
this field will be reset.

Note that all other fields of \EnactState also contain a \GovActionID
since they are \HashProtected.

\begin{figure*}[h]
\begin{code}
record EnactEnv : Set where
  constructor ⟦_,_,_⟧ᵉ
  field gid       : GovActionID
        treasury  : Coin
        epoch     : Epoch

record EnactState : Set where
  field cc            : HashProtected (Maybe ((Credential ⇀ Epoch) × ℚ))
        constitution  : HashProtected (DocHash × Maybe ScriptHash)
        pv            : HashProtected ProtVer
        pparams       : HashProtected PParams
        withdrawals   : RwdAddr ⇀ Coin

ccCreds : HashProtected (Maybe ((Credential ⇀ Epoch) × ℚ)) → ℙ Credential
ccCreds (just x   , _)  = dom (x .proj₁)
ccCreds (nothing  , _)  = ∅
\end{code}
\caption{Types and function used for the ENACT transition system}
\label{fig:enact-defs}
\end{figure*}
\begin{code}[hide]
open EnactState

private variable
  s : EnactState
  up : PParamsUpdate
  new : Credential ⇀ Epoch
  rem : ℙ Credential
  q : ℚ
  dh : DocHash
  sh : Maybe ScriptHash
  v : ProtVer
  wdrl : RwdAddr ⇀ Coin
  t : Coin
  gid : GovActionID
  e : Epoch

instance
  _ = +-0-monoid
\end{code}

Figure~\ref{fig:sts:enact} defines the rules of the ENACT transition
system. Usually no preconditions are checked, and the state is simply
updated (including the \GovActionID for the hash protection scheme, if
required). The exceptions are \NewCommittee and \TreasuryWdrl:

\begin{itemize}
\item \NewCommittee requires that maximum terms are respected, and
\item \TreasuryWdrl requires that the treasury is able to cover the sum of all withdrawals (old and new).
\end{itemize}

\begin{figure*}[h]
\begin{code}
data _⊢_⇀⦇_,ENACT⦈_ : EnactEnv → EnactState → GovAction → EnactState → Set where

  Enact-NoConf :
    ───────────────────────────────────────
    ⟦ gid , t , e ⟧ᵉ ⊢ s ⇀⦇ NoConfidence ,ENACT⦈ record  s { cc = nothing , gid }

  Enact-NewComm : let old      = maybe proj₁ ∅ (s .EnactState.cc .proj₁)
                      maxTerm  = s .pparams .proj₁ .PParams.ccMaxTermLength +ᵉ e
                  in
    ∀[ term ∈ range new ] term ≤ maxTerm
    ───────────────────────────────────────
    ⟦ gid , t , e ⟧ᵉ ⊢  s ⇀⦇ NewCommittee new rem q ,ENACT⦈
                record  s { cc = just ((new ∪ˡ old) ∣ rem ᶜ , q) , gid }

  Enact-NewConst :
    ───────────────────────────────────────
    ⟦ gid , t , e ⟧ᵉ ⊢  s ⇀⦇ NewConstitution dh sh ,ENACT⦈
                record  s { constitution = (dh , sh) , gid }

  Enact-HF :
    ───────────────────────────────────────
    ⟦ gid , t , e ⟧ᵉ ⊢ s ⇀⦇ TriggerHF v ,ENACT⦈ record s { pv = v , gid }

  Enact-PParams :
    ───────────────────────────────────────
    ⟦ gid , t , e ⟧ᵉ ⊢  s ⇀⦇ ChangePParams up ,ENACT⦈
                record  s { pparams = applyUpdate (s .pparams .proj₁) up , gid }

  Enact-Wdrl : let newWdrls = s .withdrawals ∪⁺ wdrl in
    ∑[ x ← newWdrls ] x ≤ t
    ───────────────────────────────────────
    ⟦ gid , t , e ⟧ᵉ ⊢ s ⇀⦇ TreasuryWdrl wdrl ,ENACT⦈ record s { withdrawals = newWdrls }

  Enact-Info :
    ───────────────────────────────────────
    ⟦ gid , t , e ⟧ᵉ ⊢ s ⇀⦇ Info ,ENACT⦈ s
\end{code}
\caption{ENACT transition system}
\label{fig:sts:enact}
\end{figure*}