{-# LANGUAGE CPP               #-}
{-# LANGUAGE BlockArguments    #-}
{-# LANGUAGE PatternSynonyms   #-}
{-# LANGUAGE ViewPatterns      #-}

{-# OPTIONS_GHC -Wno-name-shadowing #-}
{-# OPTIONS_GHC -Wno-unused-top-binds #-}

-- | Test suite for lab 4

import Control.Monad         (foldM, forM, void, when)

import Data.Char             ( isSpace, toUpper )
import Data.Function         ( (&) )
import qualified Data.List   as List
import Data.Monoid           ( Sum(getSum) )

import System.Console.GetOpt ( OptDescr(Option), ArgDescr(ReqArg, NoArg), pattern RequireOrder, getOpt )
import System.Directory      ( doesDirectoryExist, getCurrentDirectory, listDirectory, setCurrentDirectory
                             , exeExtension )
import System.Environment    ( getArgs, lookupEnv )
import System.Exit           ( ExitCode(..), exitFailure, exitSuccess )
import System.FilePath       ( (<.>), (</>), isRelative, joinPath, takeBaseName )
import System.IO             ( BufferMode(LineBuffering), Handle, hIsTerminalDevice, hSetBuffering, hPutStr, hPutStrLn, stderr, stdout)
import System.IO.Unsafe      ( unsafePerformIO )
import System.Process        ( readProcessWithExitCode, showCommandForUser )

-- * Configure
------------------------------------------------------------------------

-- Executable name
executable_name :: FilePath
-- You might have to add or remove .exe here if you are using Windows
executable_name = "lab4" <.> exeExtension

was_failure :: String -> Bool
was_failure = ("ERROR" `List.isInfixOf`) . map toUpper

type GoodTest  = (FilePath, String, String)
type GoodTests = [GoodTest]

defaultGoodTests :: GoodTests
defaultGoodTests =
  [ ("good/001.hs",    "-v", "7"         )
  , ("good/002.hs",    "-n", "5"         )
  , ("good/003.hs",    "-v", "5050"      )
  , ("good/004.hs",    "-v", "720"       )
  , ("good/005.hs",    "-n", "0"         )
  , ("good/006.hs",    "-v", "1073741824")
  , ("good/007.hs",    "-v", "1"         )
  , ("good/008.hs",    "-v", "210"       )
  , ("good/008.hs",    "-n", "210"       )
  , ("good/church.hs", "-v", "8"         )
  , ("good/009.hs",    "-v", "131072"    )
  , ("good/010.hs",    "-v", "1"         )
  , ("good/010.hs",    "-n", "1"         )
  , ("good/011.hs",    "-v", "1"         )
  , ("good/011.hs",    "-n", "1"         )
  , ("good/012.hs",    "-v", "0"         )
  , ("good/013.hs",    "-v", "1"         )
  , ("good/014.hs",    "-n", "33"        )
  -- The following test doesn't even type-check in Haskell,
  -- so I removed it.  (Andreas A., 2021-12-16)
  -- , ("good/015.hs",    "-v", "1"         )
  -- , ("good/015.hs",    "-n", "1"         )
  , ("good/ski.hs",    "-n", "16"        )
  , ("good/016.hs",    "-v", "18"        )
  , ("good/016.hs",    "-n", "18"        )
  , ("good/017.hs",    "-v", "2"         )
  , ("good/017.hs",    "-n", "2"         )
  , ("good/018.hs",    "-v", "2"         )
  , ("good/018.hs",    "-n", "2"         )
  , ("good/019.hs",    "-v", "0"         )
  , ("good/019.hs",    "-n", "0"         )
  , ("good/shadow.hs", "-n", "1"         )
  , ("good/shadow2.hs","-n", "1"         )
  ]

type BadTestDirs = [FilePath]

defaultBadTestDirs :: BadTestDirs
defaultBadTestDirs = ["bad"]

data Options = Options
  { makeFlag        :: Bool
  , goodTests       :: GoodTests
  , badTestDirs     :: BadTestDirs
  }

defaultOptions :: Options
defaultOptions = Options
  { makeFlag    = True
  , goodTests   = []
  , badTestDirs = []
  }

debug :: String -> IO ()
debug = putStrLn

-- * Options
------------------------------------------------------------------------

optDescr :: [OptDescr (Options -> Maybe Options)]
optDescr =
    [ Option []    ["no-make"] (NoArg  disableMake               ) "do not run make"
    , Option ['g'] ["good"]    (ReqArg addGood "FILE,MODE,RESULT") "good test case FILE, call-by-name or -value MODE, expected RESULT"
    , Option ['b'] ["bad"]     (ReqArg addBad  "FILE"            ) "bad test case FILE"
    ]
  where
    disableMake :: Options -> Maybe Options
    disableMake options = Just $ options { makeFlag = False }

    -- Parse the given program argument and add it to the 'Options' structure.
    --
    -- Fails if argument is not a triple of the form @FILE,{n,v},VALUE@.
    addGood :: String -> Options -> Maybe Options
    addGood (splitOn ',' -> [f,m,r]) options = Just $
      options { goodTests = (f,'-':m,r) : goodTests options }
    addGood _                        _       = Nothing

    addBad :: FilePath -> Options -> Maybe Options
    addBad f options = Just $
      options { badTestDirs = f : badTestDirs options }

usage :: IO a
usage = do
  hPutStrLn stderr "Usage: plt-test-lab4 [--no-make] [-g|--good FILE,MODE,RESULT]... [-b|--bad FILE]..."
  hPutStrLn stderr "           path_to_solution" -- "The path to the directory where your solution is located"
  exitFailure


-- * Main
------------------------------------------------------------------------

type TestSuite = ([(FilePath,String,String)],[FilePath])

main :: IO ()
main = do
  -- In various contexts this is guessed incorrectly
  hSetBuffering stdout LineBuffering

  -- Parse options.
  testdir <- getCurrentDirectory
  (codedir, domake, (goodTests, badTests)) <- parseArgs =<< getArgs
  let adjustPath f = if isRelative f then joinPath [testdir,f] else f
      goodTests'   = map (first3 adjustPath) goodTests
      badTests'    = map adjustPath          badTests
      lab4         = "." </> executable_name

  -- Build the SUT.
  setCurrentDirectory codedir
  when domake $ runPrgNoFail_ "make" [] ""

   -- Run the tests.
  let goodtot = length goodTests'
      badtot  = length badTests'
  goodpass <- getSum . mconcat <$> forM goodTests' (runGood lab4)
  badpass  <- getSum . mconcat <$> forM badTests'  (runBad  lab4)

  -- Report results.
  putStrLn "### Summary ###"
  putStrLn $ show goodpass <> " of " <> show goodtot <> " good tests passed."
  putStrLn $ show badpass  <> " of " <> show badtot  <> " bad tests passed (approximate check, only checks if any error at all was reported)."

  let ok = goodpass == goodtot && badpass == badtot
  if ok then exitSuccess else exitFailure

parseArgs :: [String] -> IO (FilePath, Bool, TestSuite)
parseArgs argv = case getOpt RequireOrder optDescr argv of

  (o,[codedir],[]) -> do
    Options doMake good bad <- maybe usage (return . defaultIfNoTests) $
      foldM (&) defaultOptions o
    let listHSFiles d          = map (d </>) . filter (".hs" `List.isSuffixOf`) <$> listDirectory d
    let expandPath  f          = doesDirectoryExist f >>= \b -> if b then listHSFiles f else return [f]
    let expandPathGood (f,m,r) = map (\ f' -> (f',m,r)) <$> expandPath f
    goodTests <- concat <$> mapM expandPathGood good
    badTests  <- concat <$> mapM expandPath bad
    return (codedir, doMake, (goodTests, badTests))

  (_,_,_) -> usage

-- | If no testcases were supplied on the command line, use the default set.
--
defaultIfNoTests :: Options -> Options
defaultIfNoTests options@(Options make good bad)
  | null good && null bad = Options make defaultGoodTests defaultBadTestDirs
  | otherwise             = options


-- * Run programs
------------------------------------------------------------------------

runPrgNoFail_ :: FilePath -- ^ Executable
              -> [String] -- ^ Flags
              -> String   -- ^ Standard input
              -> IO ()
runPrgNoFail_ exe flags input = void $ runPrgNoFail exe flags input

runPrgNoFail :: FilePath -- ^ Executable
             -> [String] -- ^ Flag
             -> String   -- ^ Standard input
             -> IO (String,String) -- ^ stdout and stderr
runPrgNoFail exe flags input = do
  let c = showCommandForUser exe flags
  hPutStr stderr $ "Running " ++ c ++ "... "
  (s,out,err) <- readProcessWithExitCode exe flags input
  hPutStrLnExitCode s stderr "."
  case s of
    ExitFailure x -> do
      reportError exe ("with status " ++ show x) (nullMaybe input) (nullMaybe out) (nullMaybe err)
      exitFailure
    ExitSuccess -> do
      debug $ "Standard output:\n" ++ out
      debug $ "Standard error:\n" ++ err
      return (out,err)

runGood :: FilePath -> (FilePath,String,String) -> IO (Sum Int)
runGood lab4 (file, mode, expect) = do
  putStrLn $ color blue $ "--- " <> takeBaseName file <> " ---"
  putStrLn $ "     Mode: " <> mode
  putStrLn $ "Expecting: " <> expect
  (exitval, trimEnd -> result, err) <- readProcessWithExitCode lab4 [mode, file] ""
  let
    done r = do
      -- Print standard error
      unlessNull (trimEnd err) \ err -> do
        putStrLn $ "   StdErr:"
        putStrLn $ color red err
      putStrLn ""
      return r
  if exitval /= ExitSuccess then do
      putStrLn $ color red "Error"
      done 0
  else if result == expect then do
      putStrLn $ "   Output: " ++ color green result
      done 1
  else do
      putStrLn $ "   Output: " ++ color red result
      done 0


runBad :: FilePath -> FilePath -> IO (Sum Int)
runBad lab4 bad = do
  putStrLn $ color blue $ "xxx " <> takeBaseName bad <> " xxx"
  (_,stdout1,stderr1) <- readProcessWithExitCode lab4 ["-v", bad] ""
  (_,stdout2,stderr2) <- readProcessWithExitCode lab4 ["-n", bad] ""
  let result1 = trimEnd $ stdout1 <> stderr1
      result2 = trimEnd $ stdout2 <> stderr2
  putStrLn $ "CBV: " <> result1
  putStrLn $ "CBN: " <> result2
  putStrLn ""
  return $ if was_failure result1 && was_failure result2 then 1 else 0

-- * Terminal output colors
------------------------------------------------------------------------

type Color = Int

color :: Color -> String -> String
#if defined(mingw32_HOST_OS)
color _ s = s
#else
color c s
  | haveColors = fgcol c ++ s ++ normal
  | otherwise  = s
#endif

-- | Colors are disabled if the terminal does not support them.
{-# NOINLINE haveColors #-}
haveColors :: Bool
haveColors = unsafePerformIO supportsPretty

highlight, bold, underline, normal :: String
highlight = "\ESC[7m"
bold      = "\ESC[1m"
underline = "\ESC[4m"
normal    = "\ESC[0m"

fgcol, bgcol :: Color -> String
fgcol col = "\ESC[0" ++ show (30+col) ++ "m"
bgcol col = "\ESC[0" ++ show (40+col) ++ "m"

red, green, blue, cyan, black :: Color
black = 0
red = 1
green = 2
blue = 4
cyan = 6

-- * Error reporting and output checking
------------------------------------------------------------------------

colorExitCode :: ExitCode -> String -> String
colorExitCode ExitSuccess     = color green
colorExitCode (ExitFailure _) = color red

putStrLnExitCode :: ExitCode -> String -> IO ()
putStrLnExitCode e = putStrLn . colorExitCode e

hPutStrLnExitCode :: ExitCode -> Handle -> String -> IO ()
hPutStrLnExitCode e h = hPutStrLn h . colorExitCode e

reportErrorColor :: Color
                 -> String         -- ^ command that failed
                 -> String         -- ^ how it failed
                 -> Maybe String   -- ^ given input
                 -> Maybe String   -- ^ stdout output
                 -> Maybe String   -- ^ stderr output
                 -> IO ()
reportErrorColor col c m i o e = do
    putStrLn $ color col $ c ++ " failed: " ++ m
    whenJust i $ \i -> do
                       putStrLn "Given this input:"
                       putStrLn $ color blue $ replaceNull i "<nothing>"
    whenJust o $ \o -> do
                       putStrLn "It printed this to standard output:"
                       putStrLn $ color blue $ replaceNull o "<nothing>"
    whenJust e $ \e -> do
                       putStrLn "It printed this to standard error:"
                       putStrLn $ color blue $ replaceNull e "<nothing>"

reportError :: String         -- ^ command that failed
            -> String         -- ^ how it failed
            -> Maybe String   -- ^ given input
            -> Maybe String   -- ^ stdout output
            -> Maybe String   -- ^ stderr output
            -> IO ()
reportError = reportErrorColor red

-- * General utilities
------------------------------------------------------------------------

-- Inlined from https://hackage.haskell.org/package/pretty-terminal-0.1.0.0/docs/src/System-Console-Pretty.html#supportsPretty :

-- | Whether or not the current terminal supports pretty-terminal.
supportsPretty :: IO Bool
supportsPretty =
  hSupportsANSI stdout
  where
    -- | Use heuristics to determine whether the functions defined in this
    -- package will work with a given handle.
    --
    -- The current implementation checks that the handle is a terminal, and
    -- that the @TERM@ environment variable doesn't say @dumb@ (whcih is what
    -- Emacs sets for its own terminal).
    hSupportsANSI :: Handle -> IO Bool
    -- Borrowed from an HSpec patch by Simon Hengel
    -- (https://github.com/hspec/hspec/commit/d932f03317e0e2bd08c85b23903fb8616ae642bd)
    hSupportsANSI h = (&&) <$> hIsTerminalDevice h <*> (not <$> isDumb)
      where
        isDumb = (== Just "dumb") <$> lookupEnv "TERM"

first3 :: (a -> d) -> (a,b,c) -> (d,b,c)
first3 f (a,b,c) = (f a,b,c)

splitOn :: Char -> String -> [String]
splitOn _   "" = []
splitOn sep s  = splitOn' s ""
  where
    splitOn' []     sub             = [reverse sub]
    splitOn' (c:cs) sub | c == sep  = reverse sub:splitOn' cs ""
                        | otherwise = splitOn' cs (c:sub)

whenJust :: Applicative m => Maybe a -> (a -> m ()) -> m ()
whenJust (Just a) k = k a
whenJust Nothing  _ = pure ()

ifNull :: [a] -> b -> ([a] -> b) -> b
ifNull [] b _ = b
ifNull as _ f = f as

unlessNull :: Applicative m => [a] -> ([a] -> m ()) -> m ()
unlessNull xs = ifNull xs (pure ())

replaceNull :: [a] -> [a] -> [a]
replaceNull as xs = ifNull as xs id

nullMaybe :: [a] -> Maybe [a]
nullMaybe as = ifNull as Nothing Just

trimEnd :: String -> String
trimEnd = List.dropWhileEnd isSpace
