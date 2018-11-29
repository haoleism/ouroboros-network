\subsection{Cardano.BM.Configuration.Model}
\label{module:Cardano.BM.Configuration.Model}

%if False
\begin{code}
{-# LANGUAGE OverloadedStrings   #-}

module Cardano.BM.Configuration.Model
    (
      Configuration
    , setup
    , minSeverity
    , setMinSeverity
    , inspectSeverity
    , setSeverity
    , getBackends
    , registerBackend
    , setDefaultBackends
    , getOption
    --, inspectOutput
    --, takedown
    ) where

import           Control.Concurrent.MVar (MVar, newEmptyMVar, putMVar,
                     takeMVar, withMVar)
import qualified Data.Aeson as Aeson
import qualified Data.HashMap.Strict as HM
import           Data.Text (Text, pack)

import           Cardano.BM.Data (Severity (..), Backend (..))

\end{code}
%endif

The configuration is a singleton.
\begin{code}
type ConfigurationMVar = MVar ConfigurationInternal
newtype Configuration = Configuration
    { getCG :: ConfigurationMVar }

-- Our internal state
data ConfigurationInternal = ConfigurationInternal
    { cgMapSeverity :: HM.HashMap Text Severity
    , cgMapOutput   :: HM.HashMap Text [Backend]
    , cgOptions     :: HM.HashMap Text Aeson.Object
    , cgMinSeverity :: Severity
    , cgDefBackends :: [Backend]
    }
--    options:  config.logrotation = { maxFiles = 10; maxSize = 5000000 }
--              config.logprefix = { path = "/mnt/disk/spacy" }

\end{code}

\begin{code}
getBackends :: Configuration -> Text -> IO (Maybe [Backend])
getBackends configuration name =
    withMVar (getCG configuration) $ \cg -> do
        let outs = HM.lookup name (cgMapOutput cg)
        case outs of
            Nothing -> do
                return $ Just (cgDefBackends cg)
            Just os -> return $ Just os

setDefaultBackends :: Configuration -> [Backend] -> IO ()
setDefaultBackends configuration bes = do
    cg <- takeMVar (getCG configuration)
    putMVar (getCG configuration) $ cg { cgDefBackends = bes }

registerBackend :: Configuration -> Text -> Maybe Backend -> IO ()
registerBackend _ kn f = pure () -- TODO
  --  registerBackend "some" (Just Backend { pass' = Katip.pass (show StdoutSK) })
  --  registerBackend "severe.error" (Just Backend { pass' = Katip.pass "StdoutSK::severe.log") })

\end{code}

\begin{code}
getOption :: Configuration -> Text -> IO (Maybe Text)
getOption configuration name = do
    withMVar (getCG configuration) $ \cg ->
        case HM.lookup name (cgOptions cg) of
            Nothing -> return Nothing
            Just o -> return $ Just $ pack $ show o

\end{code}

\begin{code}
minSeverity :: Configuration -> IO Severity
minSeverity configuration = withMVar (getCG configuration) $ \cg ->
    return $ cgMinSeverity cg

setMinSeverity :: Configuration -> Severity -> IO ()
setMinSeverity configuration sev = do
    cg <- takeMVar (getCG configuration)
    putMVar (getCG configuration) $ cg { cgMinSeverity = sev }

\end{code}

\begin{code}
inspectSeverity :: Configuration -> Text -> IO (Maybe Severity)
inspectSeverity configuration name =
    withMVar (getCG configuration) $ \cg ->
        return $ HM.lookup name (cgMapSeverity cg)

-- if Maybe Severity given is Nothing then the entry for this name is deleted.
setSeverity :: Configuration -> Text -> Maybe Severity -> IO ()
setSeverity configuration name sev = do
    cg <- takeMVar (getCG configuration)
    putMVar (getCG configuration) $ cg { cgMapSeverity = HM.update (const sev) name (cgMapSeverity cg) }

\end{code}

\begin{code}
setup :: Text -> IO Configuration
setup _ = do
    cgref <- newEmptyMVar
    putMVar cgref $ ConfigurationInternal HM.empty HM.empty HM.empty Debug []
    return $ Configuration cgref

\end{code}
