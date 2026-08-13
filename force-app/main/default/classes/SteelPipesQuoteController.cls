public class SteelPipesQuoteController {

    public Quote                      quoteRecord          { get; set; }
    public Map<String, Object>        jsonData             { get; set; }
    
    // 👉 Two separate lists for the different tables
    public List<Map<String, Object>>  standardLineItems    { get; set; }
    public List<Map<String, Object>>  specialLineItems     { get; set; }
    public List<String>               specialHeaderCols    { get; set; }
    
    public Decimal                    totalAmount          { get; set; }
    public Decimal                    standardTotalAmount  { get; set; }
    public Decimal                    standardTotalGst     { get; set; }
    public Decimal                    standardTotalFinal   { get; set; }
    public Decimal                    totalGstAmount       { get; set; }
    public Decimal                    totalFinalAmount     { get; set; }
    public Boolean                    isExport             { get; set; }
    public Boolean                    showRateInDocDomestic { get; set; }
    public String                     exportCurrency       { get; set; }
    public Decimal                    totalExportFobFc     { get; set; }
    public Decimal                    totalExportFobInr    { get; set; }
    public String                     todayDate            { get; set; }
    public String                     quoteNotes           { get; set; }
    public String                     contactEmail         { get; set; }
    public String                     logoBase64           { get; set; }

    public String offerNumber    { get; set; }
    public String companyAddress { get; set; }

    public Boolean                    showLumpSumFreight   { get; set; }
    public Decimal                    lumpSumFreightAmount { get; set; }
    public Boolean                    showPricePerKgFreight   { get; set; }
    public Decimal                    pricePerKgFreightAmount { get; set; }

    public SteelPipesQuoteController(ApexPages.StandardController stdController) {
        
        if (!Test.isRunningTest()) {
            stdController.addFields(new List<String>{
                'QuoteNumber', 'Opportunity.Name', 'Quote_Value__c', 'CreatedDate', 'ContactId'
            });
        }

        quoteRecord = [
            SELECT Id, Name, QuoteNumber, Quote_Value__c, CreatedDate,
                Account.Name, Account.BillingStreet, Account.BillingCity,
                Account.BillingState, Account.BillingPostalCode, Account.Phone, Account.Email__c,
                Contact.Name, Contact.Phone, Contact.Email,Quote_Reference__c,
                BillingStreet, BillingCity, BillingState, BillingPostalCode
            FROM   Quote
            WHERE  Id = :stdController.getId()
            LIMIT  1
        ];

        try {
            StaticResource sr = [SELECT Body, ContentType FROM StaticResource WHERE Name = 'UtkarshLogo' LIMIT 1];
            logoBase64 = 'data:' + sr.ContentType + ';base64,' + EncodingUtil.base64Encode(sr.Body);
        } catch(Exception e) {
            logoBase64 = '';
        }

        totalAmount = 0.00;
        totalGstAmount = 0.00;
        totalFinalAmount = 0.00;
        standardTotalAmount = 0.00;
        standardTotalGst = 0.00;
        standardTotalFinal = 0.00;
        isExport = false;
        exportCurrency = '';
        totalExportFobFc = 0.00;
        totalExportFobInr = 0.00;
        showLumpSumFreight = false;
        lumpSumFreightAmount = 0.00;
        showPricePerKgFreight = false;
        pricePerKgFreightAmount = 0.00;
        standardLineItems = new List<Map<String, Object>>();
        specialLineItems  = new List<Map<String, Object>>();
        specialHeaderCols = new List<String>();
        todayDate   = Date.today().format();
        if (quoteRecord.Contact != null && String.isNotBlank(quoteRecord.Contact.Email)) {
            contactEmail = quoteRecord.Contact.Email;
        } else if (quoteRecord.Account != null && String.isNotBlank(quoteRecord.Account.Email__c)) {
            contactEmail = quoteRecord.Account.Email__c;
        } else {
            contactEmail = '';
        }

        // Related Account's billing address, comma-joined, skipping blanks
        List<String> addrParts = new List<String>();
        if (quoteRecord.Account != null) {
            if (String.isNotBlank(quoteRecord.Account.BillingStreet))     addrParts.add(quoteRecord.Account.BillingStreet);
            if (String.isNotBlank(quoteRecord.Account.BillingCity))       addrParts.add(quoteRecord.Account.BillingCity);
            if (String.isNotBlank(quoteRecord.Account.BillingState))      addrParts.add(quoteRecord.Account.BillingState);
            if (String.isNotBlank(quoteRecord.Account.BillingPostalCode)) addrParts.add(quoteRecord.Account.BillingPostalCode);
        }
        companyAddress = String.join(addrParts, ', ');

        // Offer number: UIL/STEEL/{QuoteNumber}/{FY, Apr-Mar}
        Date qDate = quoteRecord.CreatedDate != null ? quoteRecord.CreatedDate.date() : Date.today();
        Integer fyStartYear = qDate.month() >= 4 ? qDate.year() : qDate.year() - 1;
        String fyStartStr = String.valueOf(fyStartYear);
        String fyEndStr   = String.valueOf(fyStartYear + 1);
        String fyLabel = fyStartStr.substring(fyStartStr.length() - 2) + '-' + fyEndStr.substring(fyEndStr.length() - 2);
        offerNumber = 'UIL/STEEL/' + quoteRecord.QuoteNumber + '/' + fyLabel;


        

        

        if (String.isNotBlank(quoteRecord.Quote_Value__c)) {
            try {
                jsonData = (Map<String, Object>) JSON.deserializeUntyped(quoteRecord.Quote_Value__c);
                
                // 👉 THE FIX: Safety Injector for Visualforce
                // Ensures all required VF keys exist in the map to prevent "Map key not found" crashes
               List<String> requiredVfKeys = new List<String>{
                'market_type', 'tc_offer_validity', 'tc_delivery_period',
                'tc_price_variation', 'tc_payment_terms',
                'tc_vehicle_load', 'tc_qty_tolerance', 'tc_tolerance', 'tc_inspection',
                'tc_pre_dispatch_inspection', 'tc_work_address', 'tc_gst_tin_number'
            };
                for (String key : requiredVfKeys) {
                    if (!jsonData.containsKey(key) || jsonData.get(key) == null) {
                        jsonData.put(key, '-'); 
                    }
                }

                // Defaults to 'Included' unless freight_steel_pipes is explicitly 'Ex-works'
                String transportText = 'Included'; 
                
                if (jsonData.containsKey('freight_steel_pipes') && jsonData.get('freight_steel_pipes') != null) {
                    String freightValue = String.valueOf(jsonData.get('freight_steel_pipes')).trim();
                    
                    if (freightValue.equalsIgnoreCase('Ex-works')) {
                        transportText = 'Excluded';
                    }
                }
                
                // Force the calculated word into the standard key for the Visualforce page
                jsonData.put('tc_transportation', transportText);

                // Check for Freight = 'Freight' + Transportation = 'Lump sum' → show lump sum row
                if (jsonData.containsKey('freight_steel_pipes') && jsonData.containsKey('transportation')) {
                    String fVal = String.valueOf(jsonData.get('freight_steel_pipes')).trim();
                    String tVal = String.valueOf(jsonData.get('transportation')).trim();
                    if (fVal.equalsIgnoreCase('Freight') && tVal.equalsIgnoreCase('Lump sum')) {
                        showLumpSumFreight = true;
                        if (jsonData.containsKey('transportation_charges') && jsonData.get('transportation_charges') != null) {
                            String tcStr = String.valueOf(jsonData.get('transportation_charges')).trim();
                            if (String.isNotBlank(tcStr)) {
                                lumpSumFreightAmount = Decimal.valueOf(tcStr);
                            }
                        }
                    } else if (fVal.equalsIgnoreCase('Freight') && tVal.equalsIgnoreCase('Price per kg')) {
                        showPricePerKgFreight = true;
                    }
                }
                
                // Extract Notes
                if (jsonData.containsKey('Note') && jsonData.get('Note') != null) {
                    quoteNotes = String.valueOf(jsonData.get('Note'));
                }

                showRateInDocDomestic = true;
                if (jsonData.containsKey('_showRateInDocDomestic') && jsonData.get('_showRateInDocDomestic') != null) {
                    showRateInDocDomestic = (Boolean) jsonData.get('_showRateInDocDomestic');
                }

                // 2. Separate lines into STANDARD vs. SPECIAL based on "display_type" Line Items
                if (jsonData.containsKey('_Saved_Table_Rows')) {
                    List<Object> rawRows = (List<Object>) jsonData.get('_Saved_Table_Rows');
                    Integer slNo = 1;
                    Integer colIndex = 1; 
                    
                    for (Object rowObj : rawRows) {
                        Map<String, Object> row = (Map<String, Object>) rowObj;
                        
                        // We now use static columns for Length and Special Description instead of dynamic headers
                        if (specialHeaderCols.isEmpty()) {
                            specialHeaderCols.add('Length (M)');
                            specialHeaderCols.add('Special Description');
                        }
                        
                        row.put('designation', row.get('designation') != null ? String.valueOf(row.get('designation')) : '');
                        row.put('standard_spec_grade', row.get('standard_spec_grade') != null ? String.valueOf(row.get('standard_spec_grade')) : '');
                        
                        String std = row.get('standard_spec_grade') != null ? String.valueOf(row.get('standard_spec_grade')) : '';
                        String pClass = row.get('pipe_class') != null ? String.valueOf(row.get('pipe_class')) : '';
                        String customThk = row.get('custom_thickness') != null ? String.valueOf(row.get('custom_thickness')) : '';
                        String shapeVal = row.get('shape') != null ? String.valueOf(row.get('shape')) : '';
                        
                        if (std.contains('IS 1239') || std.contains('10577')) {
                            row.put('display_class_thickness', String.isNotBlank(shapeVal) ? shapeVal : pClass);
                        } else {
                            Decimal thkVal = 0;
                            if(String.isNotBlank(customThk)){ try { thkVal = Decimal.valueOf(customThk); } catch(Exception e){} }
                            if (thkVal > 0) { row.put('display_class_thickness', customThk); } else { row.put('display_class_thickness', pClass); }
                        }
                        
                        String reflectInDoc = row.get('reflect_in_offer_doc') != null ? String.valueOf(row.get('reflect_in_offer_doc')) : 'Yes';
                        if (!reflectInDoc.equalsIgnoreCase('Yes')) {
                            row.put('display_class_thickness', '-');
                        }
                        row.put('pipe_class', pClass);
                        
                        String sizeVal = row.get('size_nb') != null ? String.valueOf(row.get('size_nb')) : '';
                        if (String.isNotBlank(sizeVal)) {
                            sizeVal = sizeVal.replaceAll('(?i)mm', '').trim();
                            if (std.containsIgnoreCase('IS 3589') || std.containsIgnoreCase('IS 1239') || std.containsIgnoreCase('IS 1161')) {
                                sizeVal += '(NB)';
                            } else if (!std.containsIgnoreCase('IS 4923')) {
                                String odVal = '';
                                if (row.get('mapped_od') != null && String.isNotBlank(String.valueOf(row.get('mapped_od')))) {
                                    odVal = String.valueOf(row.get('mapped_od'));
                                } else if (row.get('od') != null && String.isNotBlank(String.valueOf(row.get('od')))) {
                                    odVal = String.valueOf(row.get('od'));
                                }
                                
                                // Clean sizeVal to just the number for map lookup
                                String num = sizeVal.replaceAll('[^0-9.]', '');
                                
                                if (String.isBlank(odVal) || odVal == '0' || odVal == '0.0') {
                                    if (std.containsIgnoreCase('4270')) {
                                        Map<String, String> is4270 = new Map<String, String>{'100'=>'114.3', '125'=>'141.3', '150'=>'168.3', '175'=>'193.7', '200'=>'219.1', '225'=>'244.5', '250'=>'273.1', '300'=>'323.9', '350'=>'355.6', '400'=>'406.4'};
                                        if (is4270.containsKey(num)) odVal = is4270.get(num);
                                    } else if (std.containsIgnoreCase('ASTM')) {
                                        Map<String, String> astm = new Map<String, String>{'15'=>'21.3', '20'=>'26.7', '25'=>'33.4', '32'=>'42.2', '40'=>'48.3', '50'=>'60.3', '65'=>'73.0', '80'=>'88.9', '90'=>'101.6', '100'=>'114.3', '110'=>'127', '125'=>'141.3', '135'=>'152.4', '150'=>'168.3', '175'=>'193.7', '200'=>'219.1', '225'=>'244.5', '250'=>'273.0', '300'=>'323.9', '350'=>'355.6', '400'=>'406.4'};
                                        if (astm.containsKey(num)) odVal = astm.get(num);
                                    }
                                }
                                
                                if (String.isNotBlank(odVal) && odVal != '0' && odVal != '0.0') {
                                    sizeVal = odVal + '(OD)';
                                } else {
                                    sizeVal += '(OD)';
                                }
                                if (std.containsIgnoreCase('ASTM') && String.isNotBlank(shapeVal)) {
                                    sizeVal += ', ' + shapeVal.replace('-', ' ');
                                }
                            }
                        }
                        row.put('size_nb', sizeVal);

                        row.put('end_finish', row.get('end_finish') != null ? String.valueOf(row.get('end_finish')) : '');
                        
                        Decimal qty = row.get('quantity') != null ? Decimal.valueOf(String.valueOf(row.get('quantity'))) : 0.0;
                        Decimal rate = row.get('rate') != null ? Decimal.valueOf(String.valueOf(row.get('rate'))) : 0.0;
                        Decimal total = row.get('total_price') != null ? Decimal.valueOf(String.valueOf(row.get('total_price'))) : (qty * rate);
                        
                        // New Math for PDF
                        Decimal pdf_rate = 0.0;
                        Decimal pdf_base_total = 0.0;
                        Decimal pdf_gst_amount = 0.0;
                        Decimal pdf_total_price = 0.0;
                        Decimal pdf_gst_percentage = 18.0;
                        Decimal pdf_unit_price = 0.0;
                        Decimal pdf_display_unit_price = 0.0;

                        if (row.get('price_per_uom') != null) {
                            // New Logic (from updated domestic pipes LWC)
                            pdf_rate = Decimal.valueOf(String.valueOf(row.get('rate'))); // Show Rate per kg without discount
                            pdf_display_unit_price = Decimal.valueOf(String.valueOf(row.get('price_per_uom')));

                            Decimal unitGst = row.get('gst') != null ? Decimal.valueOf(String.valueOf(row.get('gst'))) : 0.0;
                            
                            if (row.get('quoted_price') != null) {
                                pdf_unit_price = Decimal.valueOf(String.valueOf(row.get('quoted_price')));
                            } else if (row.get('total_price') != null) {
                                pdf_unit_price = (Decimal.valueOf(String.valueOf(row.get('total_price'))) / qty) - unitGst;
                            } else {
                                pdf_unit_price = Decimal.valueOf(String.valueOf(row.get('price_per_uom')));
                            }
                            pdf_base_total = (pdf_unit_price * qty).setScale(2, System.RoundingMode.HALF_UP);
                            pdf_gst_amount = (unitGst * qty).setScale(2, System.RoundingMode.HALF_UP);
                            pdf_total_price = row.get('total_price') != null ? Decimal.valueOf(String.valueOf(row.get('total_price'))) : (pdf_base_total + pdf_gst_amount);
                            
                            if (pdf_unit_price > 0) {
                                pdf_gst_percentage = ((unitGst / pdf_unit_price) * 100.0).setScale(0, System.RoundingMode.HALF_UP);
                            }
                        } else {
                            // Old Logic (Backwards compatibility for existing quotes)
                            Decimal unitGst = row.get('gst') != null ? Decimal.valueOf(String.valueOf(row.get('gst'))) : 0.0;
                            Decimal gstPercentage = (rate > 0) ? (unitGst / rate) * 100.0 : 0.0;
                            gstPercentage = gstPercentage.setScale(0, System.RoundingMode.HALF_UP);
                            pdf_gst_percentage = gstPercentage;
                            
                            Decimal discountPercent = row.get('discount') != null ? Decimal.valueOf(String.valueOf(row.get('discount'))) : 0.0;
                            Decimal discountedRate = rate * (1 - (discountPercent / 100.0));
                            discountedRate = discountedRate.setScale(2, System.RoundingMode.HALF_UP);
                            
                            Decimal baseTotal = 0.0;
                            if (gstPercentage > 0) {
                                baseTotal = total / (1 + (gstPercentage / 100.0));
                            } else {
                                baseTotal = total;
                            }
                            baseTotal = baseTotal.setScale(2, System.RoundingMode.HALF_UP);
                            
                            Decimal gstAmount = total - baseTotal;
                            
                            pdf_rate = discountedRate;
                            pdf_base_total = baseTotal;
                            pdf_unit_price = qty > 0 ? (baseTotal / qty).setScale(2, System.RoundingMode.HALF_UP) : 0.0;
                            pdf_display_unit_price = pdf_unit_price;
                            pdf_gst_amount = gstAmount;
                            pdf_total_price = total;
                        }
                        
                        row.put('pdf_rate', pdf_rate);
                        row.put('pdf_unit_price', pdf_unit_price);
                        row.put('pdf_display_unit_price', pdf_display_unit_price);
                        row.put('pdf_base_total', pdf_base_total);
                        row.put('pdf_gst_amount', pdf_gst_amount);
                        row.put('pdf_total_price', pdf_total_price);
                        row.put('pdf_gst_percentage', pdf_gst_percentage);
                        
                        row.put('uom', row.get('uom') != null ? String.valueOf(row.get('uom')) : '');

                        row.put('quantity', qty);
                        row.put('rate', rate);
                        row.put('total_price', total);
                        
                        // Export Fields
                        Decimal od = row.get('od') != null ? Decimal.valueOf(String.valueOf(row.get('od'))) : 0.0;
                        Decimal wt = row.get('wall_thickness') != null ? Decimal.valueOf(String.valueOf(row.get('wall_thickness'))) : 0.0;
                        Decimal pl = row.get('pipe_length') != null ? Decimal.valueOf(String.valueOf(row.get('pipe_length'))) : 0.0;
                        Decimal kgm = row.get('kg_per_meter') != null ? Decimal.valueOf(String.valueOf(row.get('kg_per_meter'))) : 0.0;
                        Decimal tp = row.get('total_pieces') != null ? Decimal.valueOf(String.valueOf(row.get('total_pieces'))) : 0.0;
                        Decimal tm = row.get('total_meters') != null ? Decimal.valueOf(String.valueOf(row.get('total_meters'))) : 0.0;
                        Decimal tw = row.get('total_weight') != null ? Decimal.valueOf(String.valueOf(row.get('total_weight'))) : 0.0;
                        
                        String pit = row.get('price_input_type') != null ? String.valueOf(row.get('price_input_type')) : '';
                        String cc = row.get('currency_code') != null ? String.valueOf(row.get('currency_code')) : '';
                        
                        Decimal pfc = row.get('price_fc') != null ? Decimal.valueOf(String.valueOf(row.get('price_fc'))) : 0.0;
                        Decimal tfc = row.get('total_fob_fc') != null ? Decimal.valueOf(String.valueOf(row.get('total_fob_fc'))) : 0.0;
                        Decimal tfinr = row.get('total_fob_inr') != null ? Decimal.valueOf(String.valueOf(row.get('total_fob_inr'))) : 0.0;
                        
                        row.put('od', od);
                        row.put('wall_thickness', wt);
                        row.put('pipe_length', pl);
                        row.put('kg_per_meter', kgm);
                        row.put('total_pieces', tp);
                        row.put('total_meters', tm);
                        row.put('total_weight', tw);
                        row.put('price_fc', pfc);
                        row.put('total_fob_fc', tfc);
                        row.put('total_fob_inr', tfinr);

                        row.put('price_input_type', pit);
                        
                        row.put('price_per_mt_fc', tw > 0 ? (tfc / tw) : 0);
                        row.put('price_per_piece_fc', tp > 0 ? (tfc / tp) : 0);
                        
                        if (String.isNotBlank(pit)) {
                            isExport = true;
                            if (String.isBlank(exportCurrency) && String.isNotBlank(cc)) {
                                exportCurrency = cc;
                            }
                            totalExportFobFc += tfc;
                            totalExportFobInr += tfinr;
                        }
                        String cHeader = jsonData.containsKey('c' + colIndex + '_Header') ? String.valueOf(jsonData.get('c' + colIndex + '_Header')) : '';
                        String cValue  = jsonData.containsKey('c' + colIndex + '_Value')  ? String.valueOf(jsonData.get('c' + colIndex + '_Value')) : '';
                        
                        if (String.isNotBlank(cHeader) && String.isNotBlank(cValue)) {
                            row.put('customHeader', insertZeroWidthSpaces(cHeader));
                            row.put('customValue', insertZeroWidthSpaces(cValue));
                            row.put('SlNo', slNo++);
                            totalAmount += pdf_base_total;
                            totalGstAmount += pdf_gst_amount;
                            specialLineItems.add(row);
                        } else {
                            row.put('SlNo', slNo++);
                            totalAmount += pdf_base_total;
                            totalGstAmount += pdf_gst_amount;
                            standardTotalAmount += pdf_base_total;
                            standardTotalGst += pdf_gst_amount;
                            standardLineItems.add(row);
                        }
                        
                        colIndex++; 
                    }
                    
                    // Build specialValuesList aligned with our static columns (Length and Special Description)
                    for (Map<String, Object> row : standardLineItems) {
                        List<String> sVals = new List<String>();
                        String lengthVal = row.get('special_description_header') != null ? String.valueOf(row.get('special_description_header')).trim() : '';
                        String descVal   = row.get('special_description') != null ? String.valueOf(row.get('special_description')).trim() : '';
                        
                        sVals.add(String.isNotBlank(lengthVal) ? insertZeroWidthSpaces(lengthVal) : '-');
                        sVals.add(String.isNotBlank(descVal)   ? insertZeroWidthSpaces(descVal)   : '-');
                        
                        row.put('specialValuesList', sVals);
                    }
                    
                    // 👉 Add lump sum freight to standard total if applicable
                    if (showLumpSumFreight && lumpSumFreightAmount > 0) {
                        // Calculate 18% GST on the Lump Sum Freight
                        Decimal freightGst = (lumpSumFreightAmount * 0.18).setScale(2, System.RoundingMode.HALF_UP);
                        
                        standardTotalAmount += lumpSumFreightAmount;
                        standardTotalGst    += freightGst;
                        totalAmount         += lumpSumFreightAmount;
                        totalGstAmount      += freightGst;
                    }
                    
                    // 👉 Add price-per-kg freight: sum totalWeight from _configuredPipesDomestic × rate
                    if (showPricePerKgFreight && jsonData.containsKey('transportation_charges')) {
                        String tcStr = String.valueOf(jsonData.get('transportation_charges')).trim();
                        if (String.isNotBlank(tcStr)) {
                            Decimal pricePerKg = Decimal.valueOf(tcStr);
                            Decimal totalWeightKg = 0.0;
                            // _configuredPipesDomestic has the real totalWeight values
                            if (jsonData.containsKey('_configuredPipesDomestic') && jsonData.get('_configuredPipesDomestic') != null) {
                                List<Object> configPipes = (List<Object>) jsonData.get('_configuredPipesDomestic');
                                for (Object pipeObj : configPipes) {
                                    Map<String, Object> pipe = (Map<String, Object>) pipeObj;
                                    if (pipe.get('totalWeight') != null) {
                                        String wStr = String.valueOf(pipe.get('totalWeight')).trim();
                                        if (String.isNotBlank(wStr) && wStr != 'null') {
                                            totalWeightKg += Decimal.valueOf(wStr);
                                        }
                                    }
                                }
                            }
                            // Fallback: read from _Final_Apex_Lines weight
                            if (totalWeightKg == 0 && jsonData.containsKey('_Final_Apex_Lines') && jsonData.get('_Final_Apex_Lines') != null) {
                                List<Object> apexLines = (List<Object>) jsonData.get('_Final_Apex_Lines');
                                for (Object lineObj : apexLines) {
                                    Map<String, Object> line = (Map<String, Object>) lineObj;
                                    if (line.get('weight') != null) {
                                        String wStr = String.valueOf(line.get('weight')).trim();
                                        if (String.isNotBlank(wStr) && wStr != 'null') {
                                            totalWeightKg += Decimal.valueOf(wStr);
                                        }
                                    }
                                }
                            }
                            if (totalWeightKg > 0) {
                                pricePerKgFreightAmount = (totalWeightKg * pricePerKg).setScale(2, System.RoundingMode.HALF_UP);
                                
                                // Calculate 18% GST on the Per-KG Freight
                                Decimal perKgGst = (pricePerKgFreightAmount * 0.18).setScale(2, System.RoundingMode.HALF_UP);
                                
                                standardTotalAmount += pricePerKgFreightAmount;
                                standardTotalGst    += perKgGst;
                                totalAmount         += pricePerKgFreightAmount;
                                totalGstAmount      += perKgGst;
                            }
                        }
                    }
                    
                    // 👉 Calculate final totals AFTER the freight and its GST have been fully added
                    standardTotalFinal = standardTotalAmount + standardTotalGst;
                    totalFinalAmount = totalAmount + totalGstAmount;
                }
            } catch (Exception e) {
                System.debug('Error parsing Steel Pipes JSON: ' + e.getMessage());
            }
        }
    }

    public String getContactNo() {
        if (quoteRecord.Contact != null && String.isNotBlank(quoteRecord.Contact.Phone)) {
            return quoteRecord.Contact.Phone;
        }
        return (quoteRecord.Account != null) ? quoteRecord.Account.Phone : '';
    }
    
    // Helper to allow word-break in PDF for very long continuous strings without spaces
    private String insertZeroWidthSpaces(String input) {
        if (String.isBlank(input)) return input;
        
        String result = '';
        Integer count = 0;
        for (Integer i = 0; i < input.length(); i++) {
            String c = input.substring(i, i+1);
            result += c;
            if (c == ' ' || c == '-' || c == '_') {
                count = 0;
            } else {
                count++;
                if (count >= 10) {
                    result += '<br/>';
                    count = 0;
                }
            }
        }
        return result;
    }
}