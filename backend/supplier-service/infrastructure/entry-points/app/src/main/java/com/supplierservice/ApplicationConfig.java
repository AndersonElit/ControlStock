package com.supplierservice;

import org.springframework.context.annotation.ComponentScan;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.FilterType;

@Configuration
@ComponentScan(
        basePackages = {
                "com.supplierservice.usecases",
                "com.supplierservice.restapi",
                "com.supplierservice.app"
        },
        includeFilters = {
                @ComponentScan.Filter(
                        type = FilterType.REGEX,
                        pattern = ".*UseCase?$"
                )
        },
        useDefaultFilters = false
)
public class ApplicationConfig {
}
