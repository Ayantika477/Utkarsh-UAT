/*
Owner - Ayantika 
================================================================================
CLASS: TenderWrappers
--------------------------------------------------------------------------------
WHY THIS CLASS EXISTS:
All 4 Tender247 APIs return JSON in different shapes. Instead of manually
parsing Map<String,Object> everywhere (error-prone, hard to read), this class
defines typed "wrapper" classes so we can use JSON.deserialize() directly into
strongly-typed Apex objects. Every Batch class below uses these wrappers.
================================================================================
*/
public class TenderWrappers {

    // ---------------------------------------------------------------------
    // Used by: Tender Listing Data Count API (Endpoint 1)
    // ---------------------------------------------------------------------
    public class CountResponse {
        public Boolean Success;
        public String Message;
        public Integer TotalRecord;
        public List<CountData> Data;
        public Integer StatusCode;
    }
    public class CountData {
        public Integer count;
    }

    // ---------------------------------------------------------------------
    // Used by: Tender Listing Data API (Endpoint 2) AND
    //          Probable Bidders TenderId Wise API (Endpoint 3)
    // (Endpoint 3 returns the same tender fields + an extra probable_bidder list)
    // ---------------------------------------------------------------------
    public class ListingResponse {
        public Boolean Success;
        public String Message;
        public Integer TotalRecord;
        public List<TenderRecord> Data;
        public Integer StatusCode;
    }

    public class TenderRecord {
        public Long tenderid;
        public String sourcetenderid;
        public Decimal value;
        public String biddeadline;
        public Decimal emd;
        public Decimal documentcost;
        public String authority;
        public String currencyCode;
        public String tenderdetails;
        public String tenderdescription;
        public String prebidmeetingdate;
        public String datecreated;
        public String corrigenduminfo;
        public List<String> sector;
        public String sourceurl;
        public Boolean isupdated;
        public List<String> subindustry;
        public String completionofwork;
        public String ai_summary;
        public List<LocationInfo> location;
        public List<String> probable_bidder; // only present in Endpoint 3 response
        public List<DocumentInfo> documents;
        public String zipdocumentdownload;
    }

    public class LocationInfo {
        public Long tenderid;
        public String country;
        public String state;
        public String city;
    }

    public class DocumentInfo {
        public Long documentid;
        public String name;
        public String downloadLink;
        public String type;
    }

    // ---------------------------------------------------------------------
    // Used by: Probable Bidder Contact Details API (Endpoint 4)
    // ---------------------------------------------------------------------
    public class ContactDetailsResponse {
        public Boolean Success;
        public String Message;
        public Integer TotalRecord;
        public List<ContactDetailData> Data;
        public Integer StatusCode;
    }
    public class ContactDetailData {
        public String bidder_name;
        public String contact_number;
        public String email_id;
        public String pan_no;
        public String vendorcode;
        public String seller_id;
        public String gem_id;
        public String msme_number;
        public String category;
        public String branch_name;
        public String address;
        public String pincode;
        public String gst_number;
        public String phone_number;
        public String alternate_email_id;
        public String designation;
    }
}