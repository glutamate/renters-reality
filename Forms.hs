{-# LANGUAGE QuasiQuotes       #-}
{-# LANGUAGE OverloadedStrings #-}
module Forms
    ( 
    -- * Standard forms 
      landlordForm
    , landlordFromForm
    , reviewForm
    , reviewFromForm

    -- * Property search
    , AddrSearch(..)
    , landlordSearchForm
    , propertySearchForm
    , addrFromForm
    ) where

import Yesod
import BadLandlords
import Model

import Data.Time (getCurrentTime)
import Data.Maybe (fromMaybe)
import Control.Applicative ((<$>),(<*>))
import Network.Wai (remoteHost)

import qualified Data.Map as M

data AddrSearch = AddrSearch
    { addrOne   :: Maybe String
    , addrTwo   :: Maybe String
    , addrCity  :: Maybe String
    , addrState :: Maybe String
    , addrZip   :: String
    }

-- | The landlord entry is a one field input, so the button is included 
--   here. Pass the route th POST to.
landlordForm :: BadLandlordsRoute -> Widget ()
landlordForm route = [$hamlet|
    <form .landlord method="post" action="@{route}">
        <table>
            <tr>
                <th>
                    <label for="landlord">Landlord:
                <td>
                    <input .complete size=45 placeholder="Name of landlord or management company" name="landlord" required>
                <td .landlord-button>
                    <input type="submit" value="Next">
    |]

landlordFromForm :: Handler Landlord
landlordFromForm = do
    landlord <- runFormPost' $ stringInput "landlord"
    return $ Landlord landlord

reviewForm :: Landlord -> ReviewType -> Widget ()
reviewForm landlord rtype = do
    ip <- lift $ return . show . remoteHost =<< waiRequest
    [$hamlet|
    <form method="post" action=@{CreateR rtype}>
        <input type=hidden name="landlord" value=#{landlordName landlord}>
        <input type=hidden name="ip" value=#{ip}>
        <table>
            <tr>
                <th>
                    <label for="name">Your name:
                <td>
                    <input size=30 name="name" required>
            <tr>
                <th>
                    <label for="email">Your email:
                <td>
                    <input size=30 type="email" name="email" required>

            <tr .spacer>
                <td colspan="2">&nbsp;

            <tr>
                <th>
                    <label for="addrone">Address line 1:
                <td>
                    <input size=30 name="addrone" placeholder="248 Kelton St" required>
            <tr>
                <th>
                    <label for="addrtwo">Address line 2:
                <td>
                    <input size=30 name="addrtwo" placeholder="Apt 1 (optional)">
            <tr>
                <th>
                    <label for="city">City:
                <td>
                    <input size=30 name="city" required>
            <tr>
                <th>
                    <label for="state">State:
                <td>
                    <input size=30 name="state" required>
            <tr>
                <th>
                    <label for="zip">Zipcode:
                <td>
                    <input size=15 name="zip" required>

            <tr .spacer>
                <td colspan="2">&nbsp;

            <tr>
                <th>
                    <label for="review">Review:
                <td>
                    <textarea rows=10 cols=60 name="review" required>

            <tr #buttons>
                <td>&nbsp;
                <td>
                    <input type="submit">
                    <input type="reset">
    |]

reviewFromForm :: ReviewType -> Handler Review
reviewFromForm rtype = do
    now     <- liftIO getCurrentTime
    content <- runFormPost' $ stringInput "review"

    landlordId <- findOrCreate =<< landlordFromForm

    -- todo: how else to fit a fromMaybe on a single field?
    addrOne   <- runFormPost' $ stringInput "addrone"
    addrTwo   <- fmap (fromMaybe "") $ runFormPost' $ maybeStringInput "addrtwo"
    addrCity  <- runFormPost' $ stringInput "city"
    addrState <- runFormPost' $ stringInput "state"
    addrZip   <- runFormPost' $ stringInput "zip"

    propertyId <- findOrCreate $ Property addrOne addrTwo addrCity addrState addrZip

    -- establish ownership
    _ <- findOrCreate $ Ownership propertyId landlordId

    reviewerId <- findOrCreate =<<
        (runFormPost' $ Reviewer
            <$> stringInput "name"
            <*> stringInput "email"
            <*> stringInput "ip")

    ref <- newRef

    return $ Review
        { reviewReference   = ref
        , reviewType        = rtype
        , reviewCreatedDate = now
        , reviewContent     = content
        , reviewReviewer    = reviewerId
        , reviewLandlord    = landlordId
        , reviewProperty    = propertyId
        }

landlordSearchForm :: Widget ()
landlordSearchForm = [$hamlet|
    <form .landlord method="post" action="@{SearchR LandlordS}">
        <table>
            <tr>
                <th>
                    <label for="landlord">Landlord:
                <td>
                    <input .complete size=45 placeholder="Name of landlord or management company" name="landlord" required>
                <td .landlord-button>
                    <input type="submit" value="Search">
    |]

propertySearchForm :: Widget ()
propertySearchForm = [$hamlet|
    <form method="post" action=@{SearchR PropertyS}>
        <table>
            ^{tableRow "addrone" "Address line 1:" "248 Kelton St"}
            ^{tableRow "addrtwo" "Address line 2:" "Apt 1"        }
            ^{tableRow "city"    "City:"           ""             }
            ^{tableRow "state"   "State:"          ""             }
            <tr>
                <th>
                    <label for="zip">Zip:
                <td>
                    <input size=30 name="zip" required>

            <tr #buttons>
                <td>&nbsp;
                <td>
                    <input type=submit value="Search">
    |]
    where
        tableRow :: String -> String -> String -> Widget ()
        tableRow name label placeholder = [$hamlet|
            <tr>
                <th>
                    <label for=#{name}> #{label}
                <td>
                    <input size=30 name=#{name} placeholder=#{placeholder}>
            |]

addrFromForm :: Handler AddrSearch
addrFromForm = runFormPost' $ AddrSearch
    <$> maybeStringInput "addrone"
    <*> maybeStringInput "addrtwo"
    <*> maybeStringInput "city"
    <*> maybeStringInput "state"
    <*> stringInput "zip"
