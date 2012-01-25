{- |
Module      :  Web.Theory
Description :  Pretty-printing security protocol theories into HTML code.
Copyright   :  (c) 2011 Simon Meier, Cedric Staub
License     :  GPL-3

Maintainer  :  Cedric Staub <cstaub@ethz.ch>
Stability   :  experimental
Portability :  non-portable
-}

{-# LANGUAGE PatternGuards, TupleSections #-}

module Web.Theory
  ( htmlThyPath
  , htmlThyDbgPath
  , pngThyPath
  , titleThyPath
  , theoryIndex
  , nextThyPath
  , prevThyPath
  , nextSmartThyPath
  , prevSmartThyPath
  , checkProofs
  , applyMethodAtPath
  , applyProverAtPath
  )
where

import Theory
import Theory.Pretty

import Web.Types
import Web.Settings

import Data.Maybe
import Data.List
import Data.Monoid
import qualified Data.Map as M

import Control.Basics

import System.Directory
import System.FilePath

import Extension.Data.Label

import qualified Text.Dot as D
import Text.Isar
import Text.PrettyPrint.Html
import Utils.Misc (stringSHA256)

import System.Process
import System.Exit

------------------------------------------------------------------------------
-- Various other functions
------------------------------------------------------------------------------

checkProofs :: ClosedTheory -> ClosedTheory
checkProofs = proveTheory checkedProver
  where
    checkedProver = checkAndExtendProver (sorryProver "not yet proven")

applyMethodAtPath :: ClosedTheory -> String -> ProofPath
                  -> Int -> Maybe ClosedTheory
applyMethodAtPath thy lemmaName proofPath i = do
    lemma <- lookupLemma lemmaName thy
    subProof <- get lProof lemma `atPath` proofPath
    methods <- applicableProofMethodsSorted thy <$> psInfo (root subProof)
    method <- if length methods >= i then Just (methods !! (i-1)) else Nothing
    applyProverAtPath thy lemmaName proofPath 
      (oneStepProver method `mappend` 
       replaceSorryProver (oneStepProver Simplify) `mappend`
       replaceSorryProver (contradictionAndClauseProver)
      )

applyProverAtPath :: ClosedTheory -> String -> ProofPath
                  -> Prover -> Maybe ClosedTheory
applyProverAtPath thy lemmaName proofPath prover =
    modifyLemmaProof (focus proofPath prover) lemmaName thy

------------------------------------------------------------------------------
-- Pretty printing
------------------------------------------------------------------------------

-- | Reference a dot graph for the given path.
refDotPath :: HtmlDocument d => TheoryPath -> d
refDotPath path = closedTag "img" [("class", "graph"), ("src", imgPath)]
  where imgPath = "graph/" ++ joinPath' (renderPath path)

getDotPath :: String -> FilePath
getDotPath code = imageDir </> addExtension (stringSHA256 code) "dot"

-- | Create a link to a given theory path.
linkToPath :: HtmlDocument d
           => TheoryPath  -- ^ Path to link to.
           -> [String]    -- ^ Additional class
           -> d           -- ^ Document that carries the link.
           -> d
linkToPath path cls = withTag "a" [("class", classes), ("href", linkPath)]
  where
    classes = unwords $ "internal-link" : cls
    linkPath = joinPath' $ renderPath path

-- | Output some preformatted text.
preformatted :: HtmlDocument d => Maybe String -> d -> d
preformatted cl = withTag "div" [("class", classes cl)]
  where
    classes (Just cls) = "preformatted " ++ cls
    classes (Nothing) = "preformatted"

-- | Render a proof index relative to a theory path constructor.
proofIndex :: HtmlDocument d
           => (ProofPath -> TheoryPath)   -- ^ Relative addressing function
           -> Proof (Maybe Sequent, Bool) -- ^ The annotated incremental proof
           -> d
proofIndex mkPath = 
    prettyProofWith ppStep ppCase . insertPaths
  where
    isSolved = snd . fst . psInfo
    isAnnotated = isJust . fst . fst . psInfo

    isSorry ps
      | Sorry _ <- psMethod ps = True
      | otherwise = False

    markSolved = withTag "span" [("class", "hl_solved")]

    ppStep ps
      | not (isAnnotated ps) = superfluousStep ps
      | isSolved ps = (markSolved $ linkToStep ["solved"] ps) <> removeStep ps
      | isSorry ps = linkToStep ["unsolved", "sorry-step"] ps 
      | otherwise = linkToStep ["unsolved"] ps <> removeStep ps

    removeStep ps = linkToPath
      (mkPath $ snd $ psInfo ps) ["remove-step"] emptyDoc

    ppCase ps
      | isSolved ps = markSolved 
      | otherwise = id 

    superfluousStep ps = withTag "span"
      [("class","hl_superfluous unsolved")] 
      (prettyProofMethod $ psMethod ps)
    
    linkToStep cls ps = linkToPath
      (mkPath $ snd $ psInfo ps) ("proof-step" : cls)
      (prettyProofMethod $ psMethod ps)

-- | Render the indexing links for a single lemma
lemmaIndex :: HtmlDocument d
           => (ProofPath -> TheoryPath)   -- ^ Relative addressing function
           -> Lemma IncrementalProof      -- ^ The lemma
           -> d
lemmaIndex mkPath l =
    markSolved (kwLemmaModulo "E" <-> prettyLemmaName l <> colon) <->
    (linkToPath (TheoryLemma $ get lName l) ["edit-link"] editPng <->
    linkToPath (TheoryLemma $ get lName l) ["delete-link"] deletePng) $-$
    nest 2 (markSolved $ doubleQuotes $ prettyFormulaE $ get lFormulaE l) $-$
    proofIndex mkPath annotatedProof
  where
    editPng = png "/static/img/edit.png"
    deletePng = png "/static/img/delete.png" 
    png path = closedTag "img" [("class","icon"),("src",path)]

    annotatedProof = annotateProof $ get lProof l

    markSolved doc
      | solved = withTag "span" [("class", "hl_solved")] doc
      | otherwise = doc
      where
        solved = snd $ psInfo $ root annotatedProof

-- | Render the theory index.
theoryIndex :: HtmlDocument d => ClosedTheory -> d
theoryIndex thy = foldr1 ($-$)
    [ kwTheoryHeader $ get thyName thy
    , text ""
    , ruleLink
    , text ""
    , reqCasesLink "Untyped case distinctions" UntypedCaseDist
    , text ""
    , reqCasesLink "Typed case distinctions "  TypedCaseDist
    , text ""
    , vcat $ intersperse (text "") lemmas
    , text ""
    , kwEnd
    ]
  where
    mkPath path lemma = path $ get lName lemma
    lemmaIndex' lemma = lemmaIndex (mkPath TheoryProof lemma) lemma

    lemmas         = map lemmaIndex' (getLemmas thy)
    rules          = getClassifiedRules thy
    rulesInfo      = parens $ int $ length $ joinAllRules rules
    casesInfo kind =
        parens $ nCases <> comma <-> text chainInfo
      where 
        cases   = getCaseDistinction kind thy
        nChains = sum $ map (sum . unsolvedChainConstraints) cases
        nCases  = int (length cases) <-> text "cases"
        chainInfo | nChains == 0 = "all chains solved"
                  | otherwise    = show nChains ++ " chains left"
         
    bold                = withTag "strong" [] . text
    overview n info p   = linkToPath p [] (bold n <-> info)
    ruleLink            = overview "Rewriting rules" rulesInfo TheoryRules
    reqCasesLink name k = overview name (casesInfo k) (TheoryCaseDist k 0 0)

{-
-- | A snippet that explains a sequent using a rendered graph and the pretty
-- printed sequent.
sequentSnippet :: HtmlDocument d
               => Sequent     -- ^ Sequent to pretty print.
               -> TheoryPath  -- ^ The sequents path (NOT the path to its PNG)
               -> d
sequentSnippet se path = refDotPath path $-$ preformatted Nothing (prettySequent se)
-}

-- | A snippet that explains a sub-proof by displaying its proof state, the
-- open-goals, and the new cases.
subProofSnippet :: HtmlDocument d
                => ClosedTheory              -- ^ The theory context.
                -> (ProofPath -> TheoryPath) -- ^ Relative proof adressing
                -> (Int -> TheoryPath)       -- ^ Relative proof method addressing
                -> IncrementalProof          -- ^ The sub-proof.
                -> d
subProofSnippet thy mkProofPath mkPrfMethodPath prf = 
    case psInfo $ root prf of
      Nothing -> text $ "no annotated sequent / " ++ nCases ++ " sub-case(s)"
      Just se -> vcat $
        [ withTag "h3" [] (text "Graph Part of Sequent")
        , refDotPath (mkProofPath [])
        , text ""
        , withTag "h3" [] (text "Applicable Proof Methods")
        , preformatted (Just "methods") (numbered' $ proofMethods se)
        , withTag "h3" [] (text "Pretty-Printed Sequent")
        , preformatted (Just "sequent") (prettyNonGraphSequent se)
        , withTag "h3" [] (text $ nCases ++ " sub-case(s)")
        ] ++ 
        subCases
  where
    prettyPM (i, m) = linkToPath
      (mkPrfMethodPath i) ["proof-method"] (prettyProofMethod m)

    nCases   = show $ M.size $ children prf
    proofMethods = map prettyPM . zip [1..] . applicableProofMethodsSorted thy
    subCases = concatMap refSubCase $ M.toList $ children prf 
    refSubCase (name, prf') = 
        [ withTag "h4" [] (text "Case" <-> text name)
        , maybe (text "no proof state available")
                (const $ refDotPath $ mkProofPath [name])
                (psInfo $ root prf') 
        ]

-- | A Html document representing the requires case splitting theorem.
htmlCaseDistinction :: HtmlDocument d 
                    => CaseDistKind -> (Int, CaseDistinction) -> d
htmlCaseDistinction kind (j, th) =
    if null cases
      then withTag "h2" [] ppHeader $-$ withTag "h3" [] (text "No cases.")
      else vcat $ withTag "h2" [] ppHeader : cases
  where
    cases    = concatMap ppCase $ zip [1..] $ getDisj $ get cdCases th
    wrapP    = withTag "p" [("class","monospace cases")]
    nCases   = int $ length $ getDisj $ get cdCases th
    ppPrem   = nest 2 $ doubleQuotes $ prettyBigStepGoal $ get cdGoal th
    ppHeader = hsep 
      [ text "Sources of" <-> ppPrem
      , parens $ nCases <-> text "cases"
      ]
    ppCase (i, (names, (conc, se))) = 
      [ withTag "h3" [] $ fsep [ text "Source", int i, text "of", nCases
                               , text " / named ", doubleQuotes (text name) ]
      , refDotPath (TheoryCaseDist kind j i)
      , withTag "p" [] $ ppPrem <-> text "provided by conclusion" <-> prettyNodeConc conc
      , wrapP $ prettyNonGraphSequent se
      ]
      where
        name = intercalate "_" names

-- | Build the Html document showing the source cases distinctions.
reqCasesSnippet :: HtmlDocument d => CaseDistKind -> ClosedTheory -> d
reqCasesSnippet kind thy = vcat $ 
    htmlCaseDistinction kind <$> zip [1..] (getCaseDistinction kind thy)

-- | Build the Html document showing the rules of the theory.
rulesSnippet :: HtmlDocument d => ClosedTheory -> d
rulesSnippet thy = vcat
    [ ppRules "Protocol Rules"      crProtocol
    , ppRules "Construction Rules"  crConstruct
    , ppRules "Destruction Rules"   crDestruct
    , ppRules "Special Rules"       crSpecial
    ] 
  where
    rules = getClassifiedRules thy
    ppRules header l =
      withTag "h2" [] (text header) $$ withTag "p"
        [("class","monospace rules")]
        (vcat (intersperse (text "") $ map prettyRuleAC $ get l rules))

-- | Render the item in the given theory given by the supplied path.
htmlThyPath :: HtmlDocument d
            => ClosedTheory -- ^ The theory to render
            -> TheoryPath   -- ^ Path to render
            -> d
htmlThyPath thy path = go path
  where
    go TheoryRules               = rulesSnippet thy
    go (TheoryCaseDist kind _ _) = reqCasesSnippet kind thy
    go (TheoryProof l p)         = fromMaybe
                                     (text "No such lemma or proof path.")
                                     (subProofSnippet thy
                                       (mkProofPath l p)
                                       (TheoryMethod l p)
                                     <$> resolveProofPath thy l p)
    go (TheoryLemma _)      = text "Implement theory item pretty printing!"
    go _                    = text "Unhandled theory path. This is a bug."

    mkProofPath lemma path' subPath = TheoryProof lemma (path' ++ subPath)

-- | Render debug information for the item in the theory given by the path.
htmlThyDbgPath :: HtmlDocument d
               => ClosedTheory -- ^ The theory to render
               -> TheoryPath   -- ^ Path to render
               -> Maybe d
htmlThyDbgPath thy path = go path
  where
    go (TheoryProof l p) = do
      proof <- resolveProofPath thy l p
      prettySequent <$> psInfo (root proof)
    go _ = Nothing

-- | Render the image corresponding to the given theory path.
pngThyPath :: FilePath -> (Sequent -> D.Dot ()) -> ClosedTheory
           -> TheoryPath -> IO FilePath
pngThyPath dir compact thy path = go path
  where
    go (TheoryCaseDist k i j) = renderDotCode (casesDotCode k i j)
    go (TheoryProof l p)      = renderDotCode (proofPathDotCode l p)
    go _                      = error "Unhandled theory path. This is a bug."
    
    -- Get dot code for required cases
    casesDotCode k i j = D.showDot $
        compact $ snd $ snd $ cases !! (i-1) !! (j-1)
      where
        cases = map (getDisj . get cdCases) (getCaseDistinction k thy)

    -- Get dot code for proof path in lemma
    proofPathDotCode lemma proofPath =
      D.showDot $ fromMaybe (return ()) $ do
        subProof <- resolveProofPath thy lemma proofPath
        sequent <- psInfo $ root subProof
        return $ compact sequent

    -- Render a piece of dot code
    renderDotCode code = do
      let dotPath = dir </> getDotPath code
          pngPath = addExtension dotPath "png"

      pngGenerated <-
        firstSuccess [ doesFileExist pngPath
                     ,  writeFile dotPath code >> dotToPng "dot" dotPath pngPath
                     , dotToPng "fdp" dotPath pngPath ]
      return (if pngGenerated then pngPath else imageDir ++ "/img/delete.png")

    dotToPng dotCmd dotFile pngFile = do
      (ecode,_out,err) <- readProcessWithExitCode dotCmd ["-Tpng","-o",pngFile,dotFile] ""
      case ecode of
        ExitSuccess   -> return True
        ExitFailure i -> do
          putStrLn $ "dotToPng: "++dotCmd++" failed with code "
                      ++show i++" for file "++dotFile++":\n"++err
          return False

    firstSuccess [] = return False
    firstSuccess (m:ms) = do
      s <- m
      if s then return True else firstSuccess ms


-- | Get title to display for a given proof path.
titleThyPath :: ClosedTheory -> TheoryPath -> String 
titleThyPath thy path = go path
  where
    go TheoryRules                          = "Rewriting rules"
    go (TheoryCaseDist UntypedCaseDist _ _) = "Untyped case distinctions"
    go (TheoryCaseDist TypedCaseDist _ _)   = "Typed case distinctions"
    go (TheoryLemma l)                      = "Lemma: " ++ l
    go (TheoryProof l [])                   = "Lemma: " ++ l
    go (TheoryProof l p)
      | null (last p)       = "Method: " ++ methodName l p 
      | otherwise           = "Case: " ++ last p
    go _ = "Unhandled theory path"

    methodName l p =
      case resolveProofPath thy l p of
        Nothing -> "None"
        Just proof -> renderHtmlDoc $ prettyProofMethod $ psMethod $ root proof

-- | Resolve a proof path.
resolveProofPath :: ClosedTheory            -- ^ Theory to resolve in
                 -> String                  -- ^ Name of lemma
                 -> ProofPath               -- ^ Path to resolve
                 -> Maybe IncrementalProof
resolveProofPath thy lemmaName path = do
  lemma <- lookupLemma lemmaName thy
  get lProof lemma `atPath` path


------------------------------------------------------------------------------
-- Moving to next/prev proof path
------------------------------------------------------------------------------

-- | Get 'next' theory path.
nextThyPath :: ClosedTheory -> TheoryPath -> TheoryPath
nextThyPath thy = go
  where
    go TheoryMain                           = TheoryRules
    go TheoryRules                          = TheoryCaseDist UntypedCaseDist 0 0
    go (TheoryCaseDist UntypedCaseDist _ _) = TheoryCaseDist TypedCaseDist 0 0
    go (TheoryCaseDist TypedCaseDist _ _)   = fromMaybe TheoryMain firstLemma
    go (TheoryLemma lemma)                  = TheoryProof lemma []
    go (TheoryProof l p)
      | Just nextPath <- getNextPath l p = TheoryProof l nextPath
      | Just nextLemma <- getNextLemma l = TheoryProof nextLemma []
      | otherwise                        = TheoryMain
    go _                                 = TheoryMain

    lemmas = map (\l -> (get lName l, l)) $ getLemmas thy
    firstLemma = flip TheoryProof [] . fst <$> listToMaybe lemmas

    getNextPath lemmaName path = do
      lemma <- lookupLemma lemmaName thy
      let paths = map fst $ getProofPaths $ get lProof lemma
      getNextElement (== path) paths

    getNextLemma lemmaName = getNextElement (== lemmaName) (map fst lemmas)

-- | Get 'prev' theory path.
prevThyPath :: ClosedTheory -> TheoryPath -> TheoryPath
prevThyPath thy = go
  where
    go TheoryRules                          = TheoryMain
    go (TheoryCaseDist UntypedCaseDist _ _) = TheoryRules
    go (TheoryCaseDist TypedCaseDist _ _)   = TheoryCaseDist UntypedCaseDist 0 0
    go (TheoryLemma l)
      | Just prevLemma <- getPrevLemma l = TheoryProof prevLemma (lastPath prevLemma)
      | otherwise                        = TheoryCaseDist TypedCaseDist 0 0
    go (TheoryProof l p)
      | Just prevPath <- getPrevPath l p = TheoryProof l prevPath
      | Just prevLemma <- getPrevLemma l = TheoryProof prevLemma (lastPath prevLemma)
      | otherwise                        = TheoryCaseDist TypedCaseDist 0 0
    go _                                 = TheoryMain

    lemmas = map (\l -> (get lName l, l)) $ getLemmas thy

    getPrevPath lemmaName path = do
      lemma <- lookupLemma lemmaName thy
      let paths = map fst $ getProofPaths $ get lProof lemma
      getPrevElement (== path) paths

    lastPath lemmaName = last $ map fst $ getProofPaths $
      get lProof $ fromJust $ lookupLemma lemmaName thy

    getPrevLemma lemmaName = getPrevElement (== lemmaName) (map fst lemmas)

-- Get 'next' smart theory path.
nextSmartThyPath :: ClosedTheory -> TheoryPath -> TheoryPath
nextSmartThyPath thy = go
  where
    go TheoryMain                           = TheoryRules
    go TheoryRules                          = TheoryCaseDist UntypedCaseDist 0 0
    go (TheoryCaseDist UntypedCaseDist _ _) = TheoryCaseDist TypedCaseDist 0 0
    go (TheoryCaseDist TypedCaseDist   _ _) = fromMaybe TheoryMain firstLemma
    go (TheoryLemma lemma)                  = TheoryProof lemma []
    go (TheoryProof l p)
      | Just nextPath <- getNextPath l p = TheoryProof l nextPath
      | Just nextLemma <- getNextLemma l = TheoryProof nextLemma []
      | otherwise                        = TheoryMain
    go _ = TheoryMain

    lemmas = map (\l -> (get lName l, l)) $ getLemmas thy
    firstLemma = flip TheoryProof [] . fst <$> listToMaybe lemmas

    getNextPath lemmaName path = do
      lemma <- lookupLemma lemmaName thy
      let paths = getProofPaths $ get lProof lemma
      let nextSteps = snd $ break ((== path) . fst) paths
      if null nextSteps
        then Nothing
        else listToMaybe $ map fst $ filter snd $ tail nextSteps

    getNextLemma lemmaName = getNextElement (== lemmaName) (map fst lemmas)

-- Get 'prev' smart theory path.
prevSmartThyPath :: ClosedTheory -> TheoryPath -> TheoryPath
prevSmartThyPath thy = go
  where
    go TheoryRules = TheoryMain
    go (TheoryCaseDist UntypedCaseDist _ _) = TheoryRules
    go (TheoryCaseDist TypedCaseDist   _ _) = TheoryCaseDist UntypedCaseDist 0 0
    go (TheoryLemma l)
      | Just prevLemma <- getPrevLemma l   = TheoryProof prevLemma (lastPath prevLemma)
      | otherwise                          = TheoryCaseDist TypedCaseDist 0 0
    go (TheoryProof l p)
      | Just prevPath <- getPrevPath l p   = TheoryProof l prevPath
      | Just firstPath <- getFirstPath l p = TheoryProof l firstPath
      | Just prevLemma <- getPrevLemma l   = TheoryProof prevLemma (lastPath prevLemma)
      | otherwise                          = TheoryCaseDist TypedCaseDist 0 0
    go _ = TheoryMain

    lemmas = map (\l -> (get lName l, l)) $ getLemmas thy

    getFirstPath lemmaName current = do
      lemma <- lookupLemma lemmaName thy
      let paths = map fst $ getProofPaths $ get lProof lemma
      if null paths || (head paths == current)
        then Nothing
        else Just $ head paths

    getPrevPath lemmaName path = do
      lemma <- lookupLemma lemmaName thy
      let paths = getProofPaths $ get lProof lemma
      let prevSteps = filter snd $ fst $ break ((== path) . fst) paths
      if null prevSteps
        then Nothing
        else Just $ fst $ last prevSteps

    lastPath lemmaName = last $ map fst $ getProofPaths $
      get lProof $ fromJust $ lookupLemma lemmaName thy

    getPrevLemma lemmaName = getPrevElement (== lemmaName) (map fst lemmas)

-- | Extract proof paths out of a proof.
-- Boolean value in tuple indicates if path is sorry step.
getProofPaths :: LTree CaseName (ProofStep a) -> [([String], Bool)]
getProofPaths proof = ([], isSorry proof) : go proof
  where
    go = concatMap paths . M.toList . children
    paths (lbl, prf) = ([lbl], isSorry prf) : map (first (lbl:)) (go prf)

    isSorry ps
      | Sorry _ <- psMethod (root ps) = True
      | otherwise = False

-- | Get element _after_ the matching element in the list.
getNextElement :: (a -> Bool) -> [a] -> Maybe a
getNextElement _ [] = Nothing
getNextElement f (x:xs)
  | f x = listToMaybe xs
  | otherwise = getNextElement f xs

-- | Get element _before_ the matching element in the list.
getPrevElement :: (a -> Bool) -> [a] -> Maybe a
getPrevElement _ [] = Nothing
getPrevElement f (x:xs) = go x xs
  where
    go _ [] = Nothing
    go old (z:zs)
      | f z = Just old
      | otherwise = go z zs

-- | Annotate a proof for pretty printing.
-- The boolean flag indicates that the given proof step's children
-- are (a) all annotated and (b) contain no sorry steps.
annotateProof :: Proof (Maybe Sequent) -> Proof (Maybe Sequent, Bool)
annotateProof (LNode (ProofStep method sequent) children')
  | Nothing <- sequent = LNode (proofStep False) annotatedChildren
  | Sorry _ <- method  = LNode (proofStep False) annotatedChildren
  | otherwise          = LNode (proofStep checkChildren) annotatedChildren
  where
    annotatedChildren = M.map annotateProof children'
    proofStep bool = ProofStep method (sequent, bool)
    checkChildren = all (snd . psInfo . root . snd) $ M.toList annotatedChildren


------------------------------------------------------------------------------
-- Html file generation
------------------------------------------------------------------------------

{- TO BE REDONE, once interactive visualization is finished. Corresponds to
 - a pre-rendering of all relevant data.

data Viewport = LeftView | MainView | DebugView | PopupView
    deriving( Eq, Ord, Show )

type Link          = (Viewport, HtmlSnippetId)
type LinkId        = Int
type HtmlSnippet   = String
type HtmlSnippetId = Int
type DotCode       = String

data ThHtmlState = ThHtmlState
     { _thsDots     :: M.Map FilePath DotCode
     , _thsSnippets :: M.Map HtmlSnippet HtmlSnippetId
     , _thsLinks    :: M.Map LinkId [Link]
     }
     deriving( Eq, Ord, Show )

emptyThHtmlState :: ThHtmlState
emptyThHtmlState = ThHtmlState M.empty M.empty M.empty

$(mkLabels [''ThHtmlState])

type ThHtml = ReaderT (Sequent -> Sequent) (StateT ThHtmlState Fresh)

runThHtml :: (Sequent -> Sequent) -> ThHtml a -> (a, ThHtmlState)
runThHtml compress = 
    (`evalFresh` nothingUsed) 
  . (`runStateT` emptyThHtmlState) 
  . (`runReaderT` compress)

instance JSON Viewport where
        readJSON (JSString name) = case fromJSString name of 
            "Left"  -> return LeftView
            "Main"  -> return MainView
            "Debug" -> return DebugView
            "Popup" -> return PopupView
            cs      -> Error $ "readJSSON (Viewport): " ++ cs
        readJSON _ = Error "readJSSon (Viewport)"

        showJSON LeftView  = JSString $ toJSString "Left"
        showJSON MainView  = JSString $ toJSString "Main"
        showJSON DebugView = JSString $ toJSString "Debug"
        showJSON PopupView = JSString $ toJSString "Popup"


-- | Input for generation process that needs to be supplied from a caller of
-- @theoryToHtml@.
data GenerationInput = GenerationInput {
    giHeader      :: String    -- ^ Arbitrary html for the header
  , giTime        :: UTCTime   -- ^ Generation time.
  , giSystem      :: String    -- ^ Description of the system we run on.
  , giInputFile   :: FilePath  -- ^ Path to input file.
  , giTemplate    :: FilePath  -- ^ Path to template index.
  , giOutDir      :: FilePath  -- ^ Path to the output directory.
  , giTheory      :: ClosedTheory  -- ^ Theory to output.
  , giCmdLine     :: String    -- ^ The command line that was used in this call to
                               --   tamarin.
  , giCompress    :: Bool      -- ^ True if sequents should be compressed
                               -- before visualization by unsoundly dropping
                               -- information.
  }
  deriving( Show )

-- | Information about various paths relevant for generating the HTML output.
data PathInfo = PathInfo {
    inputFileCopy   :: FilePath  -- ^ Path of input file copy.
  , proofScriptFile :: FilePath  -- ^ Path of generated Isabelle proof script.
  , outDir          :: FilePath  -- ^ Output directory.
  , filesDir        :: FilePath  -- ^ Relative directory for input and output files.
  }
  deriving( Show )

-- | Compute the path info from the generation input.
pathInfo :: GenerationInput -> PathInfo
pathInfo input = info
  where
    info = PathInfo
      { inputFileCopy   = extendBaseName "_original"
      , proofScriptFile = extendBaseName "_processed"
      , outDir          = giOutDir input
      , filesDir        = "files"
      }

    extendBaseName ext = 
      filesDir info </> 
      addExtension (takeBaseName (giInputFile input) ++ ext) "spthy"

-- | Make a path that is specified relative to the output directory absolute.
mkAbsolute :: PathInfo -> FilePath -> FilePath
mkAbsolute info = (outDir info </>)

-- | Compute the list of absolute paths to directories required for generating
-- this HTML output.
requiredDirs :: PathInfo -> [FilePath]
requiredDirs info = map (mkAbsolute info) [".", imageDir, filesDir info]

-- | Prepare information gathered during the generation of the resulting
-- theories for exporting as JSON.
jsGenerationInfo :: GenerationInput
                 -> NominalDiffTime  -- ^ Proof script generation time.
                 -> JSObject JSValue
jsGenerationInfo input genTime = toJSObject $
    [ ("header",      showJSON . toJSString $ giHeader input)
    , ("time",        showJSON . toJSString . show $ giTime input)
    , ("system",      showJSON . toJSString $ giSystem input)
    , ("inputFile",   showJSON . fileLink   $ inputFileCopy paths)
    , ("proofScript", showJSON . fileLink   $ proofScriptFile paths)
    , ("commandLine", showJSON . toJSString $ giCmdLine input)
    , ("certificateStatus", showJSON . toJSString $ genTimeString) 
    ] 
  where
    paths = pathInfo input
    fileLink file = (toJSString (takeFileName file), toJSString file)
    genTimeString = "generated in " ++ show genTime

-- | Convert a security protocol theory to a HTML file visualizing it.
theoryToHtml :: GenerationInput -> IO ()
theoryToHtml input = do
    putStrLn ""
    putStrLn $ " copying template to output directory: " ++ outDir paths
    mapM_ (createDirectoryIfMissing True) $ requiredDirs paths
    copyTemplate (giTemplate input) $ outDir paths
    copyFile (giInputFile input) (mkAbsolute paths $ inputFileCopy paths)
    -- timed proof script generation
    putStr " generating proof script: " >> hFlush stdout
    genTime <- timed_ $ writeAbsolute (proofScriptFile paths) 
                          (render $ prettyClosedTheory $ giTheory input)
    putStrLn $ show genTime
    -- json output
    let thyJSON = mkThyJSON (jsGenerationInfo input genTime)
    writeAbsolute "theory.js"
      (("scytherP_theory_JSON = "++) . show $ showJSObject thyJSON "")
    -- graph generation
    putStrLn " generating visualizations using GraphViz:"
    parMkGraphs $ M.toList $ get thsDots thSt
  where
    paths = pathInfo input
    writeAbsolute = writeFile . mkAbsolute paths

    compress | giCompress input = compressSequent
             | otherwise        = id

    (thId, thSt) = runThHtml compress $ do
        thy <- htmlTheory $ giTheory input
        return $ renderHtmlDoc thy

    mkThyJSON :: JSObject JSValue -> JSObject JSValue
    mkThyJSON genInfo = toJSObject
      [ ("theory",         showJSON $ thId                              )
      , ("generationInfo", showJSON $ genInfo                           )
      , ("snippets",       showJSON $ invertMap $ get thsSnippets thSt )
      , ("links",          showJSON $             get thsLinks thSt    )
      ]

    invertMap = M.fromList . map (uncurry $ flip (,)) . M.toList

    -- create the graph corresponding to the given formula
    mkGraph (path, dotCode) msgChan = do
      let outFile = mkAbsolute paths path
          pngFile = addExtension outFile "png"
      ifM (doesFileExist pngFile) 
          (writeChan msgChan $ "using cached file: " ++ pngFile) 
          (do writeFile outFile dotCode
              graphvizDotToPng outFile pngFile msgChan
              removeFile outFile)

    -- | Convert a list of dot strings in parallel to png files, using the number of
    -- cores+1 parallel executions of the dot tool.
    parMkGraphs = 
        parCmd_ display . map mkGraph
      where
        display n i msg = 
            hPutStrLn stdout $ "  ["++showPadded i++" of "++show n++"] "++msg
          where 
            showPadded x = flushRight (length (show n)) (show x)

-- | Copy all the files referenced in the template index file to the output
-- directory.
copyTemplate :: FilePath -- ^ Path of template index file.
             -> FilePath -- ^ Output directory.
             -> IO ()
copyTemplate templateFile targetDir = do
    let templateDir = takeDirectory templateFile
    template <- readFile templateFile
    let files = filter (not.null) $ lines template
        copy file = do
          let outPath = targetDir </> file
          createDirectoryIfMissing True (takeDirectory outPath)
          copyFile (templateDir </> file) outPath
    mapM_ copy files

-}